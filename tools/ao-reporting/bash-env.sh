# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
# shellcheck shell=bash

# Preserve the owner's existing noninteractive Bash initialization.
if [ -n "${HEXPROOF_AO_PREVIOUS_BASH_ENV:-}" ] && [ -r "$HEXPROOF_AO_PREVIOUS_BASH_ENV" ]; then
    # shellcheck source=/dev/null
    . "$HEXPROOF_AO_PREVIOUS_BASH_ENV"
fi

function ao {
    if [ "${1-}" = review ] && [ "${2-}" = submit ] &&
        [ -n "${AO_REVIEW_WORKER_SESSION_ID:-}" ]; then
        command "$HEXPROOF_AO_PYTHON" -I -B "$HEXPROOF_AO_REPORT_ADAPTER" "$@"
    else
        command ao "$@"
    fi
}
