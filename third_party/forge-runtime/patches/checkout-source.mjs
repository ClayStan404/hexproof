// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

import { execFileSync } from "node:child_process";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

export function checkoutSource(directory, revision) {
    // Native Git guards include ignored files that become tracked in the new
    // revision. Disable implicit submodule recursion so each checkout gets the
    // same protection, regardless of the owner's global Git configuration.
    execFileSync("git", ["-C", directory, "checkout", "--detach",
        "--no-recurse-submodules", "--no-overwrite-ignore", revision],
        { stdio: ["ignore", "pipe", "pipe"] });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    try {
        const [directory, revision] = process.argv.slice(2);
        if (!directory || !/^[0-9a-f]{40}$/.test(revision ?? "")) {
            throw new Error("expected a source directory and an exact Git revision");
        }
        checkoutSource(directory, revision);
    } catch (error) {
        process.stderr.write(`Forge checkout failed without discarding local files: ${error.stderr ?? error.message}\n`);
        process.exitCode = 1;
    }
}
