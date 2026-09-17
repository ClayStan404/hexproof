//go:build !linux && !darwin && !windows

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package runtimepkg

import (
	"errors"
	"os"
)

func tryLockFile(*os.File, bool) (bool, error) {
	return false, errors.New("unsupported hosting platform")
}
func freeBytes(string) (uint64, error) {
	return 0, errors.New("unsupported hosting platform")
}
