// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package runtimepkg

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"testing"
)

func downloadFixture() (Asset, []byte) {
	body := []byte("a complete pinned engine distribution")
	sum := sha256.Sum256(body)
	return Asset{URL: "https://github.com/vendor/runtime", Size: int64(len(body)),
		SHA256: hex.EncodeToString(sum[:]), Format: "zip"}, body
}

type cancelledDownload struct {
	body   []byte
	cancel context.CancelFunc
}

func (r *cancelledDownload) Read(p []byte) (int, error) {
	if len(r.body) > 0 {
		n := copy(p, r.body)
		r.body = r.body[n:]
		return n, nil
	}
	r.cancel()
	return 0, context.Canceled
}
func (*cancelledDownload) Close() error { return nil }

func TestDownloadCancelResumesOnlyVerifiedRange(t *testing.T) {
	asset, body := downloadFixture()
	cache := t.TempDir()
	ctx, cancel := context.WithCancel(t.Context())
	defer cancel()
	client := &http.Client{Transport: fixtureTransport(func(r *http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 200, ContentLength: -1, Header: make(http.Header),
			Body: &cancelledDownload{body[:7], cancel}}, nil
	})}
	if _, err := downloadWithClient(ctx, cache, asset, nil, client); err == nil {
		t.Fatal("cancelled download was published")
	}
	partial := filepath.Join(cache, asset.SHA256+".zip.part")
	if data, err := os.ReadFile(partial); err != nil || !bytes.Equal(data, body[:7]) {
		t.Fatalf("cancel discarded the reusable prefix: %q / %v", data, err)
	}
	if _, err := os.Stat(filepath.Join(cache, asset.SHA256+".zip")); !os.IsNotExist(err) {
		t.Fatal("unverified partial data was exposed as a complete archive")
	}
	client.Transport = fixtureTransport(func(r *http.Request) (*http.Response, error) {
		if r.Header.Get("Range") != "bytes=7-" || r.Header.Get("Accept-Encoding") != "identity" {
			t.Fatalf("incorrect resume request: %v", r.Header)
		}
		return &http.Response{StatusCode: 206, ContentLength: int64(len(body) - 7),
			Header: http.Header{"Content-Range": {fmt.Sprintf("bytes 7-%d/%d", len(body)-1, len(body))}},
			Body:   io.NopCloser(bytes.NewReader(body[7:]))}, nil
	})
	name, err := downloadWithClient(t.Context(), cache, asset, nil, client)
	if err != nil || checkHash(t.Context(), name, asset.SHA256) != nil {
		t.Fatalf("resumed artifact was not verified: %v", err)
	}
}

func TestDownloadRangeFallbackAndMismatch(t *testing.T) {
	for _, status := range []int{200, 206} {
		t.Run(fmt.Sprint(status), func(t *testing.T) {
			asset, body := downloadFixture()
			cache := t.TempDir()
			partial := filepath.Join(cache, asset.SHA256+".zip.part")
			if err := os.WriteFile(partial, body[:7], 0600); err != nil {
				t.Fatal(err)
			}
			client := &http.Client{Transport: fixtureTransport(func(r *http.Request) (*http.Response, error) {
				return &http.Response{StatusCode: status, ContentLength: int64(len(body)),
					Header: http.Header{"Content-Range": {"bytes 0-999/1000"}}, Body: io.NopCloser(bytes.NewReader(body))}, nil
			})}
			name, err := downloadWithClient(t.Context(), cache, asset, nil, client)
			if status == 200 && (err != nil || checkHash(t.Context(), name, asset.SHA256) != nil) {
				t.Fatalf("server without range support did not restart safely: %v", err)
			}
			if status == 206 {
				if err == nil {
					t.Fatal("mismatched content range was accepted")
				}
				if data, _ := os.ReadFile(partial); !bytes.Equal(data, body[:7]) {
					t.Fatal("mismatched response modified the existing prefix")
				}
			}
		})
	}
}

func TestDownloadRetriesInterruptedBodyAndUsesPinnedMirror(t *testing.T) {
	asset, body := downloadFixture()
	asset.Mirrors = []string{"https://mirror.example/runtime"}
	var sources []string
	client := &http.Client{Transport: fixtureTransport(func(r *http.Request) (*http.Response, error) {
		sources = append(sources, r.URL.Host)
		data, code := body[:7], 200
		header := make(http.Header)
		if len(sources) > 1 {
			if r.Header.Get("Range") != "bytes=7-" {
				t.Fatal("automatic retry did not preserve the prefix")
			}
			data, code = body[7:], 206
			header.Set("Content-Range", fmt.Sprintf("bytes 7-%d/%d", len(body)-1, len(body)))
		}
		return &http.Response{StatusCode: code, ContentLength: -1, Header: header, Body: io.NopCloser(bytes.NewReader(data))}, nil
	})}
	name, err := downloadWithClient(t.Context(), t.TempDir(), asset, nil, client)
	if err != nil || checkHash(t.Context(), name, asset.SHA256) != nil || len(sources) != 2 || sources[1] != "mirror.example" {
		t.Fatalf("verified mirror retry failed: %v / %v", sources, err)
	}
	m := Pinned()
	mirrored, err := MirrorAssets(m, "https://mirror.example/hexproof")
	if err != nil || mirrored.Forge.SHA256 != m.Forge.SHA256 || mirrored.Forge.Size != m.Forge.Size || len(mirrored.Forge.Mirrors) != 1 {
		t.Fatal("local mirror changed artifact identity")
	}
	for _, invalid := range []string{"http://mirror.example", "https://user:secret@mirror.example", "https://mirror.example/?secret=1"} {
		if _, err := MirrorAssets(m, invalid); err == nil {
			t.Fatalf("unsafe mirror accepted: %s", invalid)
		}
	}
}
