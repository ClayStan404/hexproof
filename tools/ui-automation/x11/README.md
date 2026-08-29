<!--
SPDX-License-Identifier: GPL-3.0-or-later
SPDX-FileCopyrightText: 2026 Hexproof contributors
-->

# X11 UI automation helpers

These small tools support real-window visual verification of the Hexproof Qt
client. They are intentionally separate from the client build and are useful
only in an active X11 session.

## Build

From the repository root:

```sh
cmake -S tools/ui-automation/x11 -B build/ui-automation
cmake --build build/ui-automation
```

The build requires CMake, a C compiler, and the Xlib development files.

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

Window IDs are session-local and must be resolved again after restarting the
application. Restrict capture and input to the Hexproof window. These helpers
do not bypass Wayland isolation; use environment-provided Wayland automation
when no X11-compatible display is available.
