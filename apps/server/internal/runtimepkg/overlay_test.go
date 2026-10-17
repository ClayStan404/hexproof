// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package runtimepkg

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestOverlayPinsSourceIdentityAndRepairsPrivateCopy(t *testing.T) {
	root := t.TempDir()
	installed := Installation{Root: root, RuntimeID: Pinned().RuntimeID}
	makeJar := func(identity string) (string, string) {
		var buffer bytes.Buffer
		archive := zip.NewWriter(&buffer)
		member, err := archive.Create("META-INF/hexproof-overlay.json")
		if err != nil {
			t.Fatal(err)
		}
		if err := json.NewEncoder(member).Encode(map[string]any{"schemaVersion": 1,
			"runtimeId": identity, "baseRuntimeId": installed.RuntimeID,
			"baseManifestSha256": Pinned().ForgeManifestSHA256}); err != nil {
			t.Fatal(err)
		}
		if err := archive.Close(); err != nil {
			t.Fatal(err)
		}
		path := filepath.Join(t.TempDir(), "bundled.jar")
		if err := os.WriteFile(path, buffer.Bytes(), 0600); err != nil {
			t.Fatal(err)
		}
		sum := sha256.Sum256(buffer.Bytes())
		return path, hex.EncodeToString(sum[:])
	}
	jar, checksum := makeJar("adapter-current")
	path, err := InstallOverlay(t.Context(), installed, jar, checksum, "adapter-current")
	if err != nil {
		t.Fatal(err)
	}
	if err := checkHash(t.Context(), path, checksum); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("damaged cache"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := InstallOverlay(t.Context(), installed, jar, checksum, "adapter-current"); err != nil {
		t.Fatal(err)
	}
	if err := checkHash(t.Context(), path, checksum); err != nil {
		t.Fatal(err)
	}
	if _, err := InstallOverlay(t.Context(), installed, jar, checksum, "adapter-other"); err == nil {
		t.Fatal("accepted a mismatched runtime identity")
	}
	other, otherChecksum := makeJar("adapter-other")
	if _, err := InstallOverlay(t.Context(), installed, other, otherChecksum, "adapter-current"); err == nil {
		t.Fatal("accepted a different adapter with an otherwise valid checksum")
	}
	if err := os.WriteFile(jar, []byte("modified package"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := InstallOverlay(t.Context(), installed, jar, checksum, "adapter-current"); err == nil {
		t.Fatal("accepted damaged packaged code because a cached adapter exists")
	}
}
