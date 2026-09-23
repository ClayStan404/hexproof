// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"errors"
	"os/exec"
	"syscall"
)

func configurePlatformProcess(command *exec.Cmd) {
	command.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
}

func invalidExecutableError(err error) bool {
	// CreateProcess reports bad executable format or machine-type mismatch
	// using Win32 errors rather than the portable ENOEXEC value.
	return errors.Is(err, syscall.ENOEXEC) || errors.Is(err, syscall.Errno(193)) || errors.Is(err, syscall.Errno(216))
}
