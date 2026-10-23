#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Write the protocol identity shipped with the checksummed release assets."""

import argparse
import json
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", args.version):
        parser.error("use the validated release version")
    root = Path(__file__).resolve().parents[1]
    schema = json.loads((root / "protocol/v2/wire-schema.json").read_text())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({"schemaVersion": 1,
                                      "applicationVersion": args.version,
                                      "gameProtocol": schema["protocol"]}, indent=2) + "\n")


if __name__ == "__main__":
    main()
