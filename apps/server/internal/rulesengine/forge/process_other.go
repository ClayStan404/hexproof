//go:build !windows

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import "os/exec"

func configurePlatformProcess(command *exec.Cmd) {}
