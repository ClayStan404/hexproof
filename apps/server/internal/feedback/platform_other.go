// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

//go:build !linux

package feedback

import "os"

func lockStore(string) (*os.File, error) { return nil, ErrUnavailable }
func freeBytes(string) (int64, error)    { return 0, ErrUnavailable }
