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

func processSignal(exit *exec.ExitError) string {
	status, ok := exit.Sys().(syscall.WaitStatus)
	if !ok {
		return "other"
	}
	switch status.Signal() {
	case syscall.SIGKILL:
		return "killed"
	case syscall.SIGTERM:
		return "terminated"
	case syscall.SIGABRT:
		return "aborted"
	case syscall.SIGSEGV:
		return "segmentation_fault"
	default:
		return "other"
	}
}
