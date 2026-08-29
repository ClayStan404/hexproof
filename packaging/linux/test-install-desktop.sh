#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

package_root="${tmp_dir}/Hex proof % package"
home_dir="${tmp_dir}/home"
mkdir -p \
    "${package_root}/bin" \
    "${package_root}/share/applications" \
    "${package_root}/share/icons/hicolor/16x16/apps" \
    "${home_dir}"
cp "${script_dir}/install-desktop.sh" "${package_root}/install-desktop.sh"
cp "${script_dir}/io.github.claystan404.hexproof.desktop" \
    "${package_root}/share/applications/io.github.claystan404.hexproof.desktop"
printf 'not-a-real-png' > \
    "${package_root}/share/icons/hicolor/16x16/apps/io.github.claystan404.hexproof.png"
printf '#!/usr/bin/env bash\nexit 0\n' > "${package_root}/bin/hexproof"
chmod +x "${package_root}/install-desktop.sh" "${package_root}/bin/hexproof"

(
    cd -- "${package_root}"
    HOME="${home_dir}" ./install-desktop.sh ./bin/hexproof
)

desktop_file="${home_dir}/.local/share/applications/io.github.claystan404.hexproof.desktop"
icon_file="${home_dir}/.local/share/icons/hicolor/16x16/apps/io.github.claystan404.hexproof.png"
expected_binary="${package_root}/bin/hexproof"
expected_exec="Exec=\"${expected_binary//%/%%}\""

test -f "${desktop_file}"
test -f "${icon_file}"
grep -Fx "${expected_exec}" "${desktop_file}"
test "$(stat -c '%a' "${desktop_file}")" = 644

# Regression: a binary path containing backslash and dollar characters.
# desktop_exec_quote must emit four backslashes per literal backslash and two
# backslashes per literal dollar (freedesktop Desktop Entry Spec: the general
# string-escape rule runs before the quoting rule). tmp_dir from mktemp holds
# no reserved characters, so only the package_root2 segment is escaped.
package_root2="${tmp_dir}/Hex\\proof\$pkg"
home_dir2="${tmp_dir}/home2"
mkdir -p \
    "${package_root2}/bin" \
    "${package_root2}/share/applications" \
    "${package_root2}/share/icons/hicolor/16x16/apps" \
    "${home_dir2}"
cp "${script_dir}/install-desktop.sh" "${package_root2}/install-desktop.sh"
cp "${script_dir}/io.github.claystan404.hexproof.desktop" \
    "${package_root2}/share/applications/io.github.claystan404.hexproof.desktop"
printf 'not-a-real-png' > \
    "${package_root2}/share/icons/hicolor/16x16/apps/io.github.claystan404.hexproof.png"
printf '#!/usr/bin/env bash\nexit 0\n' > "${package_root2}/bin/hexproof"
chmod +x "${package_root2}/install-desktop.sh" "${package_root2}/bin/hexproof"

(
    cd -- "${package_root2}"
    HOME="${home_dir2}" ./install-desktop.sh ./bin/hexproof
)

desktop_file2="${home_dir2}/.local/share/applications/io.github.claystan404.hexproof.desktop"
# Expected: literal '\' -> four backslashes, literal '$' -> two backslashes + '$'.
expected_exec2='Exec="'"${tmp_dir}"'/Hex\\\\proof\\$pkg/bin/hexproof"'

test -f "${desktop_file2}"
grep -Fx "${expected_exec2}" "${desktop_file2}"
