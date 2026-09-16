#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Open the offline QML Forge UI study with isolated application directories."""

import argparse
import os
from pathlib import Path
import shutil

from prepare_assets import prepare


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare-assets", action="store_true")
    parser.add_argument("--scene", choices=["board", "response", "target", "payment",
                                           "combat", "commander", "crowded"], default="board")
    parser.add_argument("--capture-dir", type=Path)
    args = parser.parse_args()
    source = Path(__file__).resolve().parent
    work = source.parents[1] / "build" / "forge-ui-prototype"
    assets = work / "assets"
    if args.prepare_assets:
        prepare(assets)
    executable = shutil.which("qml6") or shutil.which("qml")
    if executable is None:
        parser.error("Qt's qml6/qml runner is required; use the installed Qt toolchain.")
    if any(not (assets / (key + "-full.jpg")).is_file() for key in ["bolt", "isamaru", "thalia"]):
        parser.error("Card images are missing. Run with --prepare-assets to refresh the cache.")
    arguments = [executable, str(source / "qml" / "Main.qml"), "--",
                 "--scene=" + args.scene, "--assets=" + assets.as_uri() + "/"]
    if args.capture_dir:
        args.capture_dir.mkdir(parents=True, exist_ok=True)
        arguments.append("--capture-dir=" + str(args.capture_dir.resolve()))
    environment = os.environ.copy()
    for variable, name in [("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache"),
                           ("XDG_DATA_HOME", "data")]:
        path = work / "profile" / name
        path.mkdir(parents=True, exist_ok=True)
        environment[variable] = str(path)
    os.execve(executable, arguments, environment)


if __name__ == "__main__":
    main()
