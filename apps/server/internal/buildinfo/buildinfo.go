// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package buildinfo exposes values injected by release builds.
package buildinfo

// Version is replaced through go build -ldflags for release artifacts.
var Version = "1.0.5"
