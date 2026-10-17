#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Run the Phase candidate with the shared bounded Rust compiler driver."""

import importlib.util
from pathlib import Path


driver = Path(__file__).resolve().parents[1] / "rust/run.py"
spec = importlib.util.spec_from_file_location("native_qualification_driver", driver)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

if __name__ == "__main__":
    raise SystemExit(module.main("phase"))
