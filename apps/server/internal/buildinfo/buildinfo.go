// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package buildinfo exposes values injected by release builds.
package buildinfo

// Version is replaced through go build -ldflags for release artifacts.
var Version = "1.0.0"
