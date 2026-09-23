//go:build !linux && !darwin && !windows

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package runtimepkg

import "os"

func isDiskSpaceError(error) bool { return false }

func tryLockFile(*os.File, bool) (bool, error) {
	return false, failure("unsupported_platform", "unsupported hosting platform")
}
func freeBytes(string) (uint64, error) {
	return 0, failure("unsupported_platform", "unsupported hosting platform")
}
