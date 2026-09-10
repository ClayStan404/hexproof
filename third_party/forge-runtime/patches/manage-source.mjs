// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Validate the exact downstream delta; never discard or overwrite source edits.
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const [mode, source, manabrewRevision, forgeRevision, patchRevision] = process.argv.slice(2);
const patchDirectory = dirname(fileURLToPath(import.meta.url));

function git(directory, ...args) {
    return execFileSync("git", ["-C", directory, ...args], {
        encoding: "utf8",
        maxBuffer: 16 * 1024 * 1024,
        stdio: ["ignore", "pipe", "pipe"],
    });
}

try {
    if (!["verify", "preflight", "apply"].includes(mode) || !source || !patchRevision) {
        throw new Error("expected verify|preflight|apply SOURCE MANABREW FORGE PATCH_REVISION");
    }
    const manifest = JSON.parse(readFileSync(join(patchDirectory, "manifest.json"), "utf8"));
    if (manifest.manabrewRevision !== manabrewRevision
            || manifest.forgeRevision !== forgeRevision
            || manifest.patchRevision !== patchRevision) {
        throw new Error("downstream patch manifest does not match VERSIONS.env");
    }
    if (!/^[a-zA-Z0-9.-]+\.patch$/.test(manifest.patch)) {
        throw new Error("invalid downstream patch filename");
    }
    const patchPath = join(patchDirectory, manifest.patch);
    const patch = readFileSync(patchPath, "utf8");
    if (createHash("sha256").update(patch).digest("hex") !== manifest.sha256) {
        throw new Error("downstream patch checksum mismatch");
    }
    // A regenerated checksum cannot make a truncated unified diff valid.
    // Check syntax before cloning or touching any upstream checkout.
    execFileSync("git", ["apply", "--numstat", patchPath], {
        stdio: ["ignore", "pipe", "pipe"],
    });
    if (mode !== "verify") {
        // Staged or untracked work is never treated as a managed build patch.
        if (git(source, "diff", "--cached", "--name-only").trim()
                || git(source, "ls-files", "--others", "--exclude-standard").trim()) {
            throw new Error("Forge source has staged or untracked changes; use a clean build directory");
        }
        const forgeSource = join(source, "forge");
        if (existsSync(join(forgeSource, ".git"))
                && git(forgeSource, "status", "--porcelain", "--untracked-files=normal").trim()) {
            throw new Error("Forge submodule has local changes; refusing to overwrite them");
        }
        const sourceDiff = () => git(source, "diff", "--no-ext-diff", "--no-textconv",
            "--binary", "--full-index", "--no-color", "--src-prefix=a/", "--dst-prefix=b/", "HEAD");
        const current = git(source, "rev-parse", "HEAD").trim();
        const diff = sourceDiff();
        let state = "clean";
        if (diff) {
            if (current !== manabrewRevision || diff !== patch) {
                throw new Error("Forge source has changes outside the exact managed patch; "
                    + "preserve them and choose a clean HEXPROOF_FORGE_SOURCE_DIR");
            }
            git(source, "apply", "--reverse", "--check", patchPath);
            state = "patched";
        }
        if (mode === "apply") {
            if (current !== manabrewRevision
                    || git(forgeSource, "rev-parse", "HEAD").trim() !== forgeRevision) {
                throw new Error("cannot apply downstream patch to mismatched upstream revisions");
            }
            if (state === "clean") {
                git(source, "apply", "--check", patchPath);
                git(source, "apply", patchPath);
            }
            if (sourceDiff() !== patch) {
                throw new Error("applied downstream source delta differs from the manifest patch");
            }
            process.stdout.write(`Forge downstream patch revision ${patchRevision} verified.\n`);
        } else {
            process.stdout.write(state + "\n");
        }
    }
} catch (error) {
    process.stderr.write(`Forge source verification failed: ${error.message}\n`);
    process.exitCode = 1;
}
