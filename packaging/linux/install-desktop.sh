#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# SPDX-FileCopyrightText: 2026 Hexproof contributors
#
# Install a desktop entry and hicolor icons to ~/.local so GNOME/Wayland
# shows the Hexproof taskbar icon. GNOME matches the window app_id (set
# via QGuiApplication::setDesktopFileName) to an installed .desktop file.
#
# Works both from an unpacked release tarball (bin/hexproof next to this
# script) and from a source checkout (build/client-qt/hexproof). Pass an
# explicit binary path as $1 to override.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

canonicalize_binary() {
    local candidate="$1"
    local directory

    directory="$(cd -- "$(dirname -- "${candidate}")" && pwd -P)"
    printf '%s/%s\n' "${directory}" "$(basename -- "${candidate}")"
}

desktop_exec_quote() {
    local value="$1"

    if [[ "${value}" == *$'\n'* || "${value}" == *$'\r'* || "${value}" == *'='* ]]; then
        echo "error: executable path cannot contain line breaks or '='." >&2
        return 1
    fi

    # Desktop Entry Exec values apply both string escaping and argument
    # quoting. Backslashes therefore need four literal backslashes, while
    # quotes, dollars, and backticks need quoting escapes. Percent signs are
    # doubled so they cannot be interpreted as field codes.
    value="$(printf '%s' "${value}" | sed \
        -e 's/\\/\\\\\\\\/g' \
        -e 's/"/\\\\"/g' \
        -e 's/`/\\\\`/g' \
        -e 's/\$/\\\\$/g' \
        -e 's/%/%%/g')"
    printf '"%s"' "${value}"
}

# Locate the binary: explicit arg, tarball layout, then source layout.
binary="${1:-}"
if [[ -z "${binary}" ]]; then
    for candidate in "${script_dir}/bin/hexproof" "${script_dir}/../../build/client-qt/hexproof"; do
        if [[ -x "${candidate}" ]]; then
            binary="${candidate}"
            break
        fi
    done
fi

if [[ -z "${binary}" || ! -x "${binary}" ]]; then
    echo "error: hexproof binary not found or not executable." >&2
    echo "       pass the path explicitly: $0 /path/to/hexproof" >&2
    exit 1
fi
binary="$(canonicalize_binary "${binary}")"

# Locate the desktop template and icon tree (tarball layout first).
desktop_src=""
for candidate in \
    "${script_dir}/share/applications/io.github.claystan404.hexproof.desktop" \
    "${script_dir}/../../packaging/linux/io.github.claystan404.hexproof.desktop"; do
    if [[ -f "${candidate}" ]]; then
        desktop_src="${candidate}"
        break
    fi
done
icons_src=""
for candidate in \
    "${script_dir}/share/icons/hicolor" \
    "${script_dir}/../../apps/client-qt/assets/icons/hicolor"; do
    if [[ -d "${candidate}" ]]; then
        icons_src="${candidate}"
        break
    fi
done

if [[ -z "${desktop_src}" || -z "${icons_src}" ]]; then
    echo "error: could not locate the .desktop template or hicolor icons." >&2
    exit 1
fi

desktop_dst="${HOME}/.local/share/applications/io.github.claystan404.hexproof.desktop"
exec_line="Exec=$(desktop_exec_quote "${binary}")"

echo "Installing desktop entry -> ${binary}"
mkdir -p "$(dirname -- "${desktop_dst}")"
desktop_tmp="$(mktemp "${desktop_dst}.XXXXXX")"
cleanup_desktop_tmp() {
    rm -f -- "${desktop_tmp}"
}
trap cleanup_desktop_tmp EXIT
found_exec=false
while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" == Exec=* ]]; then
        printf '%s\n' "${exec_line}"
        found_exec=true
    else
        printf '%s\n' "${line}"
    fi
done < "${desktop_src}" > "${desktop_tmp}"
if [[ "${found_exec}" != true ]]; then
    echo "error: desktop template does not contain an Exec entry." >&2
    exit 1
fi
install -m 0644 "${desktop_tmp}" "${desktop_dst}"
rm -f -- "${desktop_tmp}"
trap - EXIT

echo "Installing hicolor icons"
find "${icons_src}" -type f -name '*.png' | while IFS= read -r src; do
    rel="${src#"${icons_src}/"}"
    dst="${HOME}/.local/share/icons/hicolor/${rel}"
    mkdir -p "$(dirname -- "${dst}")"
    cp "${src}" "${dst}"
done

echo "Refreshing desktop + icon caches"
gtk-update-icon-cache -f "${HOME}/.local/share/icons/hicolor" 2>/dev/null || true
update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true

echo "Done. Launch Hexproof from the application menu or run ${binary}."
