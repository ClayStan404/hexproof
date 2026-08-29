#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -euo pipefail

if rg --pcre2 -n -U \
    '\bText\s*\{(?!\s*textFormat\s*:\s*Text\.PlainText)' \
    apps/client-qt/qml -g '*.qml'; then
    echo "Every QML Text item must declare Text.PlainText first." >&2
    exit 1
fi

if rg --pcre2 -n -U \
    '(?s)\bMenu(?:Item|Separator)\s*\{[^}]*?\bvisible\s*:' \
    apps/client-qt/qml -g '*.qml'; then
    echo "Conditionally visible menu rows must use ConditionalMenuItem or ConditionalMenuSeparator." >&2
    exit 1
fi

echo "QML text safety ok"
