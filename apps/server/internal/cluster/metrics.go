// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package cluster

import (
	"os"
	"runtime"
	"strconv"
	"strings"
)

// HostMetrics is advisory. Capacity limits remain authoritative on platforms
// without these Linux counters. Unknown memory is zero, never unlimited slots.
func HostMetrics() (availableMB int64, load float64) {
	if runtime.GOOS != "linux" {
		return
	}
	if raw, err := os.ReadFile("/proc/meminfo"); err == nil {
		for _, line := range strings.Split(string(raw), "\n") {
			fields := strings.Fields(line)
			if len(fields) >= 2 && fields[0] == "MemAvailable:" {
				value, _ := strconv.ParseInt(fields[1], 10, 64)
				availableMB = max(0, value/1024)
			}
		}
	}
	if raw, err := os.ReadFile("/proc/loadavg"); err == nil {
		if fields := strings.Fields(string(raw)); len(fields) > 0 {
			value, _ := strconv.ParseFloat(fields[0], 64)
			load = max(0, value/float64(runtime.NumCPU()))
		}
	}
	return
}
