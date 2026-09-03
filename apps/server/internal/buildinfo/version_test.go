// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package buildinfo

import (
	"os"
	"regexp"
	"testing"
)

// TestVersionMatchesClientCmakeLiteral guards the dev-flow version handshake.
// The server rejects any client whose version differs from buildinfo.Version
// (handler_session.go), and plain `go build` uses this Go literal instead of
// the release -ldflags injection. Keep the two literals in sync or dev-built
// servers hard-refuse freshly built clients.
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
			"bump both together or dev-built servers will reject the client",
			Version, literal[1])
	}
}
