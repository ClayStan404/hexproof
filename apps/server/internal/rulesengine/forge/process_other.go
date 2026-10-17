//go:build !windows

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"errors"
	"os/exec"
	"syscall"
)

func configurePlatformProcess(command *exec.Cmd) {}

func invalidExecutableError(err error) bool { return errors.Is(err, syscall.ENOEXEC) }
