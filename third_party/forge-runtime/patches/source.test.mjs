// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync, spawnSync } from "node:child_process";
import { copyFileSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { checkoutSource } from "./checkout-source.mjs";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));

test("the packaged downstream patch has valid unified-diff syntax", () => {
    const manifest = JSON.parse(readFileSync(join(scriptDirectory, "manifest.json"), "utf8"));
    const result = spawnSync("git", ["apply", "--numstat", join(scriptDirectory, manifest.patch)],
        { encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /forge-harness/);
});

function fixture(t) {
    const root = mkdtempSync(join(tmpdir(), "hexproof-forge-source-test-"));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    const source = join(root, "source");
    const patches = join(root, "patches");
    const forge = join(source, "forge");
    mkdirSync(forge, { recursive: true });
    mkdirSync(patches);
    const git = (directory, ...args) => execFileSync("git", ["-C", directory,
        "-c", "user.name=Hexproof source test", "-c", "user.email=source-test@example.invalid",
        "-c", "commit.gpgSign=false", "-c", `core.hooksPath=${join(root, "no-hooks")}`,
        "-c", "init.templateDir=", ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    git(forge, "init", "--quiet");
    git(forge, "commit", "--quiet", "--allow-empty", "-m", "fixture");
    const forgeRevision = git(forge, "rev-parse", "HEAD").trim();
    git(source, "init", "--quiet");
    writeFileSync(join(source, "example.txt"), "upstream\n");
    git(source, "add", "example.txt");
    git(source, "update-index", "--add", "--cacheinfo", `160000,${forgeRevision},forge`);
    git(source, "commit", "--quiet", "-m", "fixture");
    const manabrewRevision = git(source, "rev-parse", "HEAD").trim();
    writeFileSync(join(source, "example.txt"), "downstream\n");
    const patch = git(source, "diff", "--no-ext-diff", "--no-textconv", "--binary",
        "--full-index", "--no-color", "--src-prefix=a/", "--dst-prefix=b/", "HEAD");
    writeFileSync(join(source, "example.txt"), "upstream\n");
    writeFileSync(join(patches, "fixture.patch"), patch);
    const manifest = { patchRevision: "1", manabrewRevision, forgeRevision,
        patch: "fixture.patch", sha256: createHash("sha256").update(patch).digest("hex") };
    writeFileSync(join(patches, "manifest.json"), JSON.stringify(manifest));
    copyFileSync(join(scriptDirectory, "manage-source.mjs"), join(patches, "manage-source.mjs"));
    const run = (mode, revision = "1") => spawnSync(process.execPath,
        [join(patches, "manage-source.mjs"), mode, source, manabrewRevision, forgeRevision, revision],
        { encoding: "utf8" });
    return { root, source, patches, forge, git, run };
}

test("applies only the exact pinned delta and supports repeat builds", (t) => {
    const f = fixture(t);
    assert.equal(f.run("verify").status, 0);
    assert.equal(f.run("preflight").stdout, "clean\n");
    assert.equal(f.run("apply").status, 0);
    assert.equal(readFileSync(join(f.source, "example.txt"), "utf8"), "downstream\n");
    assert.equal(f.run("preflight").stdout, "patched\n");
    assert.equal(f.run("apply").status, 0);
});

test("rejects user edits even in a managed patch file and never overwrites them", (t) => {
    const f = fixture(t);
    assert.equal(f.run("apply").status, 0);
    writeFileSync(join(f.source, "example.txt"), "downstream\nowner change\n");
    for (const mode of ["preflight", "apply"]) {
        const result = f.run(mode);
        assert.equal(result.status, 1);
        assert.match(result.stderr, /changes outside the exact managed patch/);
    }
    assert.equal(readFileSync(join(f.source, "example.txt"), "utf8"), "downstream\nowner change\n");
});

test("rejects staged, untracked, and submodule changes", (t) => {
    const f = fixture(t);
    writeFileSync(join(f.source, "owner.txt"), "preserve\n");
    assert.match(f.run("preflight").stderr, /staged or untracked/);
    f.git(f.source, "add", "owner.txt");
    assert.match(f.run("preflight").stderr, /staged or untracked/);
    const g = fixture(t);
    writeFileSync(join(g.forge, "owner.txt"), "preserve\n");
    assert.match(g.run("preflight").stderr, /submodule has local changes/);
});

test("rejects mismatched metadata and corrupted patches before touching source", (t) => {
    const f = fixture(t);
    assert.match(f.run("apply", "2").stderr, /manifest does not match/);
    writeFileSync(join(f.patches, "fixture.patch"), "corrupt\n");
    assert.match(f.run("apply").stderr, /checksum mismatch/);
    assert.equal(readFileSync(join(f.source, "example.txt"), "utf8"), "upstream\n");
});

test("rejects a changed Forge gitlink", (t) => {
    const f = fixture(t);
    f.git(f.forge, "commit", "--quiet", "--allow-empty", "-m", "other fixture revision");
    assert.match(f.run("apply").stderr, /changes outside the exact managed patch/);
});

test("rejects invalid diff syntax even with a matching checksum", (t) => {
    const f = fixture(t);
    const patch = "diff --git a/example.txt b/example.txt\n"
        + "--- a/example.txt\n+++ b/example.txt\n"
        + "@@ -1,99 +1,99 @@\n-upstream\n+downstream\n";
    writeFileSync(join(f.patches, "fixture.patch"), patch);
    const manifestPath = join(f.patches, "manifest.json");
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    manifest.sha256 = createHash("sha256").update(patch).digest("hex");
    writeFileSync(manifestPath, JSON.stringify(manifest));
    assert.equal(f.run("verify").status, 1);
    assert.equal(readFileSync(join(f.source, "example.txt"), "utf8"), "upstream\n");
});

test("checkout preserves ignored file collisions in the harness and Forge submodule", (t) => {
    const f = fixture(t);
    for (const directory of [f.source, f.forge]) {
        const previous = f.git(directory, "rev-parse", "HEAD").trim();
        writeFileSync(join(directory, "collision.txt"), "new upstream file\n");
        f.git(directory, "add", "collision.txt");
        f.git(directory, "commit", "--quiet", "-m", "new upstream fixture");
        const next = f.git(directory, "rev-parse", "HEAD").trim();
        checkoutSource(directory, previous);
        const exclude = f.git(directory, "rev-parse", "--git-path", "info/exclude").trim();
        mkdirSync(dirname(join(directory, exclude)), { recursive: true });
        writeFileSync(join(directory, exclude), "collision.txt\n");
        writeFileSync(join(directory, "collision.txt"), "owner ignored file\n");
        assert.equal(f.git(directory, "status", "--porcelain"), "");
        assert.throws(() => checkoutSource(directory, next));
        assert.equal(readFileSync(join(directory, "collision.txt"), "utf8"), "owner ignored file\n");
        assert.equal(f.git(directory, "rev-parse", "HEAD").trim(), previous);
    }
});
