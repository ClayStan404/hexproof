// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package buildinfo

import (
	"os"
	"regexp"
	"testing"
)

// TestVersionMatchesClientCmakeLiteral keeps default source release metadata
// coherent. Deployment may retain older server releases: admission depends on
// the communication protocol, never this application version.
func TestVersionMatchesClientCmakeLiteral(t *testing.T) {
	const cmakePath = "../../../../apps/client-qt/CMakeLists.txt"
	raw, err := os.ReadFile(cmakePath)
	if err != nil {
		t.Fatalf("read %s: %v", cmakePath, err)
	}
	// Only the plain literal assignment; the override branch assigns a
	// ${HEXPROOF_VERSION_OVERRIDE} reference and must not match.
	literal := regexp.MustCompile(
		`(?m)^set\(HEXPROOF_VERSION "([0-9][^"]*)"\)$`).FindSubmatch(raw)
	if literal == nil {
		t.Fatalf("no HEXPROOF_VERSION literal found in %s", cmakePath)
	}
	if string(literal[1]) != Version {
		t.Fatalf("buildinfo.Version = %q, CMakeLists HEXPROOF_VERSION = %q; "+
			"keep default release metadata coherent; mixed releases remain protocol-compatible",
			Version, literal[1])
	}
}
