// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package runtimepkg

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"hexproof/server/internal/forgehost"
)

type fixtureTransport func(*http.Request) (*http.Response, error)

func (f fixtureTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func TestPinnedIdentityAndPlatforms(t *testing.T) {
	m := Pinned()
	if m.SchemaVersion != 1 || m.RuntimeID != forgehost.BaseRuntimeID || len(m.ForgeManifestSHA256) != 64 {
		t.Fatal("incompatible embedded manifest")
	}
	for _, platform := range []string{"linux-amd64", "windows-amd64", "darwin-arm64"} {
		asset, ok := m.Java[platform]
		if !ok || asset.Size < 1 || len(asset.SHA256) != 64 || !strings.HasPrefix(asset.URL, "https://github.com/adoptium/") {
			t.Fatalf("invalid platform %s", platform)
		}
	}
}

func TestDownloadVerifiesAndCachesWithoutPartialPublication(t *testing.T) {
	body := []byte("pinned distribution")
	sum := sha256.Sum256(body)
	asset := Asset{URL: "https://github.com/vendor/runtime", Size: int64(len(body)), SHA256: hex.EncodeToString(sum[:]), Format: "zip"}
	for _, mode := range []string{"valid", "corrupt", "oversized", "cancelled", "wrong-status"} {
		t.Run(mode, func(t *testing.T) {
			cache := t.TempDir()
			ctx, cancel := context.WithCancel(t.Context())
			defer cancel()
			calls := 0
			client := &http.Client{Transport: fixtureTransport(func(r *http.Request) (*http.Response, error) {
				calls++
				data := append([]byte{}, body...)
				code := http.StatusOK
				if mode == "corrupt" {
					data[0] ^= 1
				}
				if mode == "oversized" {
					data = append(data, 1)
				}
				if mode == "wrong-status" {
					code = http.StatusNotFound
				}
				if mode == "cancelled" {
					cancel()
					return nil, ctx.Err()
				}
				return &http.Response{StatusCode: code, ContentLength: -1, Body: io.NopCloser(bytes.NewReader(data)), Header: make(http.Header)}, nil
			})}
			name, err := downloadWithClient(ctx, cache, asset, nil, client)
			if mode != "valid" {
				if err == nil {
					t.Fatal("invalid download was published")
				}
				entries, _ := os.ReadDir(cache)
				if len(entries) != 0 {
					t.Fatal("partial cache survived")
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if checkHash(ctx, name, asset.SHA256) != nil {
				t.Fatal("stored wrong bytes")
			}
			if _, err := downloadWithClient(ctx, cache, asset, nil, client); err != nil || calls != 1 {
				t.Fatal("verified cache was downloaded again")
			}
			if err := os.WriteFile(name, bytes.Repeat([]byte{0}, len(body)), 0600); err != nil {
				t.Fatal(err)
			}
			if _, err := downloadWithClient(ctx, cache, asset, nil, client); err != nil || calls != 2 {
				t.Fatalf("damaged archive not repaired: %v", err)
			}
		})
	}
}

func TestArchiveRejectsEscapesAndSpecialEntries(t *testing.T) {
	for _, fixture := range []struct {
		name   string
		kind   byte
		target string
	}{
		{"../escape", tar.TypeReg, ""}, {"/absolute", tar.TypeReg, ""},
		{"C:/absolute", tar.TypeReg, ""}, {"a\\b", tar.TypeReg, ""},
		{"link", tar.TypeSymlink, "../escape"}, {"link", tar.TypeSymlink, "/absolute"},
		{"link", tar.TypeLink, "../escape"}, {"pipe", tar.TypeFifo, ""},
	} {
		t.Run(fixture.name+fixture.target, func(t *testing.T) {
			archive := filepath.Join(t.TempDir(), "test.tar.gz")
			file, err := os.Create(archive)
			if err != nil {
				t.Fatal(err)
			}
			gz := gzip.NewWriter(file)
			tw := tar.NewWriter(gz)
			if err := tw.WriteHeader(&tar.Header{Name: fixture.name, Typeflag: fixture.kind, Linkname: fixture.target}); err != nil {
				t.Fatal(err)
			}
			tw.Close()
			gz.Close()
			file.Close()
			if err := extract(t.Context(), archive, "tar.gz", t.TempDir()); err == nil {
				t.Fatal("unsafe archive accepted")
			}
		})
	}
	archive := filepath.Join(t.TempDir(), "test.zip")
	file, _ := os.Create(archive)
	zw := zip.NewWriter(file)
	entry, _ := zw.Create("../escape")
	entry.Write([]byte("escape"))
	zw.Close()
	file.Close()
	if err := extract(t.Context(), archive, "zip", t.TempDir()); err == nil {
		t.Fatal("zip traversal accepted")
	}
}

func TestJavaIntegrityDetectsDamageAndCancellation(t *testing.T) {
	root := t.TempDir()
	java := filepath.Join(root, javaDirectory, "bin")
	if err := os.MkdirAll(java, 0700); err != nil {
		t.Fatal(err)
	}
	exe := filepath.Join(java, "java")
	if err := os.WriteFile(exe, []byte("fixture executable"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := writeJavaIntegrity(t.Context(), root); err != nil {
		t.Fatal(err)
	}
	if err := verifyJavaIntegrity(t.Context(), root); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	if err := verifyJavaIntegrity(ctx, root); err == nil {
		t.Fatal("ignored cancellation")
	}
	os.WriteFile(exe, []byte("damaged executable"), 0700)
	if err := verifyJavaIntegrity(t.Context(), root); err == nil {
		t.Fatal("accepted changed Java")
	}
}
