#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Export immutable Git blobs using the invoking checkout's trusted public policy."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import tempfile
import unicodedata


class ExportError(ValueError):
    """A source tree, policy, or destination does not meet the export contract."""


def _canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def _digest(value):
    return hashlib.sha256(_canonical(value)).hexdigest()


def _path(value):
    if not isinstance(value, str) or not value or value.startswith("/") or "\\" in value:
        raise ExportError(f"Unsafe export path: {value!r}")
    parts = value.split("/")
    if any(part in ("", ".", "..") or part.casefold() == ".git" or ":" in part
           or part.endswith((".", " ")) for part in parts) or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ExportError(f"Unsafe export path: {value!r}")
    return value


def _unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ExportError(f"Duplicate policy field: {key}")
        result[key] = value
    return result


def load_policy(policy_path):
    policy = json.loads(Path(policy_path).read_text(encoding="utf-8"), object_pairs_hook=_unique_pairs)
    if not isinstance(policy, dict) or set(policy) != {"schemaVersion", "include", "exclude"} or type(policy["schemaVersion"]) is not int or policy["schemaVersion"] != 1:
        raise ExportError("Unsupported public export policy")
    for name in ("include", "exclude"):
        values = policy[name]
        if not isinstance(values, list) or (name == "include" and not values):
            raise ExportError(f"Invalid policy {name}")
        seen = set()
        for value in values:
            _path(value)
            if any(c in value for c in "*?[]") or value in seen:
                raise ExportError(f"Policy paths must be unique literal paths: {value!r}")
            seen.add(value)
    return policy


def policy_digest(policy_path):
    """SHA-256 of validated policy encoded as sorted compact UTF-8 JSON."""
    return _digest(load_policy(policy_path))


def _selected(path, policy):
    def matches(prefixes):
        return any(path == prefix or path.startswith(prefix + "/") for prefix in prefixes)
    return matches(policy["include"]) and not matches(policy["exclude"])


def _git_command(repo, *args):
    # Raw object access never executes a candidate's scripts, filters, or hooks.
    return ["git", "--no-replace-objects", "--literal-pathspecs", "-c", "core.fsmonitor=false",
            "-c", "core.hooksPath=/dev/null", "-C", str(repo), *args]


def _git_environment():
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    env["GIT_OPTIONAL_LOCKS"] = "0"
    return env


def _git(repo, *args):
    result = subprocess.run(_git_command(repo, *args), env=_git_environment(), capture_output=True)
    if result.returncode:
        raise ExportError(f"Git {args[0]} failed: {result.stderr.decode('utf-8', errors='replace').strip()}")
    return result.stdout


def _repo_root(repo):
    return Path(os.fsdecode(_git(repo, "rev-parse", "--show-toplevel")).strip()).resolve()


def _commit(repo, commit):
    if not isinstance(commit, str) or not re.fullmatch(r"(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})", commit):
        raise ExportError("An exact 40- or 64-hex committed object ID is required")
    commit = commit.lower()
    if _git(repo, "cat-file", "-t", commit).strip() != b"commit":
        raise ExportError("Source object must be a commit, not a tag, tree, or blob")
    return commit


def _safe_paths(paths):
    seen = {}
    components = {}
    all_paths = set(paths)
    for path in paths:
        _path(path)
        normalized = unicodedata.normalize("NFC", path).casefold()
        if normalized in seen:
            raise ExportError(f"Colliding export paths: {seen[normalized]!r}, {path!r}")
        seen[normalized] = path
        for length in range(1, len(path.split("/")) + 1):
            prefix = "/".join(path.split("/")[:length])
            normalized_prefix = unicodedata.normalize("NFC", prefix).casefold()
            previous = components.setdefault(normalized_prefix, prefix)
            if previous != prefix:
                raise ExportError(f"Colliding export paths: {previous!r}, {prefix!r}")
        if any(str(parent) in all_paths for parent in PurePosixPath(path).parents if str(parent) != "."):
            raise ExportError(f"A file or symlink is an export ancestor: {path!r}")


def _archive_attributes(path, content):
    if PurePosixPath(path).name != ".gitattributes":
        return
    for line in content.decode("utf-8").splitlines():
        if line.lstrip().startswith("#"):
            continue
        if re.search(r"(?:^|\s)[!-]?(?:export-ignore|export-subst)(?:\s|=|$)", line):
            raise ExportError(f"Archive-changing attributes are not supported: {path}")


def _link_target(path, value, files):
    if not value or value.startswith("/") or "\\" in value or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ExportError(f"Unsafe symlink target at {path!r}")
    parts = list(PurePosixPath(path).parent.parts)
    target_parts = value.split("/")
    for index, part in enumerate(target_parts):
        if part in ("", "."):
            continue
        if part == "..":
            if not parts:
                raise ExportError(f"Symlink escapes export: {path!r}")
            parts.pop()
        else:
            _path(part)
            parts.append(part)
        if index < len(target_parts) - 1 and "/".join(parts) in files:
            raise ExportError(f"Symlink traverses a file or another link: {path!r}")
    target = "/".join(parts)
    # Restrict links to exported regular files; no chains, directories, or private targets.
    if target not in files or files[target]["mode"] == "120000":
        raise ExportError(f"Symlink must reference an exported regular file: {path!r}")
    return value


def tree_manifest(root, *, ignore_git=False):
    """Hash file bytes, Git executable modes and safe symlink targets; never follow links.

    Set ignore_git only for a Git checkout: its root .git metadata is omitted.
    Untracked files are otherwise included, so they cannot disappear from comparison.
    """
    root = Path(root)
    if root.is_symlink() or not root.is_dir():
        raise ExportError("Tree root must be a real directory")
    files = {}
    for directory, dirs, names in os.walk(root, followlinks=False):
        if ignore_git and Path(directory) == root:
            dirs[:] = [name for name in dirs if name != ".git"]
            names = [name for name in names if name != ".git"]
        for name in list(dirs):
            _path((Path(directory) / name).relative_to(root).as_posix())
            if (Path(directory) / name).is_symlink():
                dirs.remove(name)
                names.append(name)
        for name in names:
            absolute = Path(directory) / name
            path = absolute.relative_to(root).as_posix()
            _path(path)
            mode = absolute.lstat().st_mode
            if stat.S_ISLNK(mode):
                target = os.readlink(absolute)
                data = os.fsencode(target)
                entry = {"path": path, "mode": "120000", "sha256": hashlib.sha256(data).hexdigest(), "linkTarget": target}
            elif stat.S_ISREG(mode):
                data = absolute.read_bytes()
                _archive_attributes(path, data)
                entry = {"path": path, "mode": "100755" if mode & 0o111 else "100644", "sha256": hashlib.sha256(data).hexdigest()}
            else:
                raise ExportError(f"Unsupported file type: {path!r}")
            files[path] = entry
    _safe_paths(files)
    for path, entry in files.items():
        if entry["mode"] == "120000":
            _link_target(path, entry["linkTarget"], files)
    manifest = {"schemaVersion": 1, "files": [files[path] for path in sorted(files)]}
    return {**manifest, "exportTreeDigest": _digest(manifest)}


def tree_digest(root, *, ignore_git=False):
    return tree_manifest(root, ignore_git=ignore_git)["exportTreeDigest"]


def compare_trees(expected, actual, *, ignore_git=False):
    return tree_digest(expected, ignore_git=ignore_git) == tree_digest(actual, ignore_git=ignore_git)


def _target_path(repo, target):
    target = Path(target)
    if not target.is_absolute():
        raise ExportError("Output directory must be an absolute path")
    if target.is_symlink():
        raise ExportError("Output directory must not be a symlink")
    target = target.resolve()
    if target == repo or repo in target.parents:
        raise ExportError("Output directory must be outside the private working tree")
    if target.exists() and (not target.is_dir() or any(target.iterdir())):
        raise ExportError("Output directory must be empty")
    return target


def export_snapshot(repo, commit, target, policy_path):
    """Export exact committed blobs; policy_path must come from a trusted checkout.

    The returned private manifest is never placed in the public tree. HEAD and
    worktree dirtiness do not affect this immutable API. Existing output is never
    overwritten. Git archive attributes, gitlinks and escaping links are refused.
    """
    repo = _repo_root(repo)
    commit = _commit(repo, commit)
    policy = load_policy(policy_path)
    target = _target_path(repo, target)
    entries = []
    for item in _git(repo, "ls-tree", "-r", "-z", "--full-tree", commit).split(b"\0"):
        if not item:
            continue
        metadata, raw_path = item.split(b"\t", 1)
        path = raw_path.decode("utf-8")
        if not _selected(path, policy):
            continue
        mode, kind, object_id = metadata.decode("ascii").split()
        if kind != "blob" or mode not in ("100644", "100755", "120000"):
            raise ExportError(f"Unsupported Git entry at {path!r}: {mode} {kind}")
        entries.append((path, mode, object_id))
    _safe_paths([entry[0] for entry in entries])
    if not entries:
        raise ExportError("Public export selection is empty")
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".public-export-", dir=target.parent) as temporary:
        staging = Path(temporary) / "tree"
        staging.mkdir()
        process = subprocess.Popen(_git_command(repo, "cat-file", "--batch"), env=_git_environment(),
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            for path, mode, object_id in entries:
                process.stdin.write((object_id + "\n").encode("ascii"))
                process.stdin.flush()
                header = process.stdout.readline().split()
                if len(header) != 3 or header[:2] != [object_id.encode("ascii"), b"blob"]:
                    raise ExportError(f"Invalid Git object response for {path!r}")
                size = int(header[2])
                data = process.stdout.read(size)
                if len(data) != size or process.stdout.read(1) != b"\n":
                    raise ExportError(f"Incomplete Git blob for {path!r}")
                destination = staging / path
                destination.parent.mkdir(parents=True, exist_ok=True)
                if mode == "120000":
                    # Validate the whole link graph before creating any symlink.
                    destination.write_bytes(data)
                else:
                    destination.write_bytes(data)
                    destination.chmod(0o755 if mode == "100755" else 0o644)
            process.stdin.close()
            if process.wait(timeout=30):
                raise ExportError("Git blob reader failed")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()
            process.stderr.close()
            if not process.stdin.closed:
                process.stdin.close()
        file_modes = {path: {"mode": mode} for path, mode, _ in entries}
        links = {}
        for path, mode, _ in entries:
            if mode == "120000":
                value = (staging / path).read_bytes().decode("utf-8")
                links[path] = _link_target(path, value, file_modes)
        for path, value in links.items():
            (staging / path).unlink()
            (staging / path).symlink_to(value)
        tree = tree_manifest(staging)
        # Recheck before publishing the complete tree; rename refuses nonempty directories.
        _target_path(repo, target)
        os.replace(staging, target)
    return {"schemaVersion": 1, "sourceCommit": commit, "exportPolicyDigest": _digest(policy),
            "exportTreeDigest": tree["exportTreeDigest"]}


def _clean_head(repo, policy):
    # Use literal selected files, not candidate-controlled Git pathspec magic.
    changed = []
    for staged in ([], ["--cached"]):
        changed += _git(repo, "diff", *staged, "--no-ext-diff", "--no-textconv", "--no-renames",
                        "--name-only", "-z", "--").split(b"\0")
    untracked = _git(repo, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0")
    if any(path and _selected(path.decode("utf-8"), policy) for path in changed + untracked):
        raise ExportError("Exported paths have uncommitted changes; commit them before exporting HEAD.")
    return os.fsdecode(_git(repo, "rev-parse", "HEAD")).strip()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--commit")
    source.add_argument("--head-clean", action="store_true")
    parser.add_argument("--target", required=True)
    parser.add_argument("--policy", required=True)
    parser.add_argument("--manifest", help="Private receipt path outside the public output tree")
    args = parser.parse_args(argv)
    try:
        if args.manifest:
            receipt = Path(args.manifest)
            if receipt.is_symlink():
                raise ExportError("Manifest must not be a symlink")
            receipt = receipt.resolve()
            target = Path(args.target).resolve()
            if receipt == target or target in receipt.parents or receipt.exists():
                raise ExportError("Manifest must be a new file outside the public output tree")
        commit = _clean_head(args.repo, load_policy(args.policy)) if args.head_clean else args.commit
        result = export_snapshot(args.repo, commit, args.target, args.policy)
        if args.manifest:
            receipt.parent.mkdir(parents=True, exist_ok=True)
            fd = os.open(receipt, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                json.dump(result, stream, indent=2)
                stream.write("\n")
        print(json.dumps(result, sort_keys=True))
    except (ExportError, OSError, UnicodeError, json.JSONDecodeError, subprocess.SubprocessError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
