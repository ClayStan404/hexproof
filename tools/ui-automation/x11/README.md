<!--
SPDX-License-Identifier: GPL-3.0-or-later
SPDX-FileCopyrightText: 2026 Hexproof contributors
-->

# X11 UI automation helpers

These small tools support real-window visual verification of the Hexproof Qt
client. They are intentionally separate from the client build and are useful
only in an active X11 session.

Use these helpers when a requested visual/input behavior needs native
verification, not after every code edit. Use isolated
test profiles and a local server, identify the exact test window, and stop only
the processes started for the check. The helpers do not authorize interaction
with an existing live game or capture of unrelated desktop content.

## Build

From the repository root:

```sh
cmake -S tools/ui-automation/x11 -B build/ui-automation
cmake --build build/ui-automation
```

The build requires CMake, a C compiler, and the Xlib and XTest development files.

## Usage

List named X11 windows and find the Hexproof client window ID:

```sh
./build/ui-automation/xwindow-list
```

Capture one window to a binary PPM image:

```sh
./build/ui-automation/xshot 0x4200011 /tmp/hexproof.ppm
```

Convert the capture when ImageMagick is available:

```sh
magick /tmp/hexproof.ppm /tmp/hexproof.png
```

Send a left-button drag using coordinates local to the target window:

```sh
./build/ui-automation/xdrag 0x4200011 100 200 600 200
```

Use identical start and end coordinates for a click:

```sh
./build/ui-automation/xdrag 0x4200011 500 300 500 300
```

Inspect a file chooser without sending input, using the exact PID recorded by
the isolated client's startup artifact and the exact translated dialog title:

```sh
./build/ui-automation/xfile-dialog --inspect 12345 'Import card database'
```

Select an existing file through that chooser's keyboard interface:

```sh
./build/ui-automation/xfile-dialog 12345 'Import card database' \
  /absolute/test-fixtures/cards.sqlite /absolute/test-output/catalog-dialog
```

Save a new file through the application's existing save dialog:

```sh
./build/ui-automation/xfile-dialog --save 12345 'Save deck list' \
  /absolute/test-output/deck.txt /absolute/test-output/deck-save-dialog
```

Open mode requires a readable existing regular file. Save mode requires a new
target and an existing writable parent directory; it rejects existing files,
directories and dangling symlinks. It checks the destination again before
pressing Return, never creates a placeholder, and never approves an overwrite
confirmation. The JSON response records the selected `open` or `save` mode.

`xfile-dialog` accepts exactly one visible `_NET_WM_WINDOW_TYPE_DIALOG` whose
`_NET_WM_PID` and title match. Its `WM_TRANSIENT_FOR` chain must lead to another
visible window of the same PID. Before every XTest key combination it verifies
the focus is within the same dialog and rechecks ownership. A short X server
grab protects the complete combination, including modifier releases, from
concurrent focus changes. It sends Ctrl+L, Ctrl+A, the path, and Return; loss of
focus aborts. It does not change focus, paste through the clipboard, remap keys, invoke an
application API, or use a different file-dialog backend. The current helper
requires printable ASCII paths representable by the active keyboard map.

The JSON response records the PID, selected dialog, transient owner, exact
title, key count and outcome. Success after input requires the dialog to close
within ten seconds; the caller must separately assert that the application
accepted and installed the selected file. An optional artifact base writes
the same JSON to a new `.json` file and refuses to overwrite existing output.
Callers running inside Qt must continue processing events while the helper
runs so an in-process GTK chooser can receive its input. External portal
windows with a different PID are rejected rather than controlled implicitly.

The ownership regression uses a simulated X server boundary and never opens
desktop windows. It verifies exact identity, transient ownership, ambiguity,
ownership/focus changes before input, complete modifier release and keyboard mapping.
It also uses isolated temporary files to verify open/save path requirements
and preserve the contents of rejected overwrite targets.

```sh
ctest --test-dir build/ui-automation --output-on-failure
```

Window IDs are session-local and must be resolved again after restarting the
application. Restrict capture and input to the Hexproof window. These helpers
do not bypass Wayland isolation; use environment-provided Wayland automation
when no X11-compatible display is available.
