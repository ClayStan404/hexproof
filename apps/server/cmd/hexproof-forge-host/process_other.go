//go:build !windows

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package main

// The pinned NativeHost closes its game and exits on stdin EOF. The Go
// supervisor additionally kills/reaps it when its own parent pipe closes.
func initializeProcessGuard() error { return nil }
