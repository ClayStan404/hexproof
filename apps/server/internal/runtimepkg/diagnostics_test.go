// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package runtimepkg

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestErrorDiagnosticsPreserveCausesWithoutErrorText(t *testing.T) {
	private := "private-user-secret-token"
	cases := []struct {
		name string
		err  error
		code string
	}{
		{"permission", &os.PathError{Op: "open", Path: "/home/" + private, Err: os.ErrPermission}, "permission_denied"},
		{"missing", &os.PathError{Op: "open", Path: private, Err: os.ErrNotExist}, "file_missing"},
		{"disk", ErrDiskSpace, "disk_space"},
		{"cancel", context.Canceled, "cancelled"},
		{"deadline", context.DeadlineExceeded, "timeout"},
		{"dns", &net.DNSError{Name: private, Server: private, Err: private}, "dns_failed"},
		{"tls", &tls.CertificateVerificationError{Err: x509.UnknownAuthorityError{}}, "tls_failed"},
		{"tls-record", tls.RecordHeaderError{Msg: private}, "tls_failed"},
		{"tls-alert", tls.AlertError(40), "tls_failed"},
		{"network", &net.OpError{Op: "dial", Net: "tcp", Err: errors.New(private)}, "network_failed"},
		{"url", &url.Error{Op: "Get", URL: "https://" + private + "/?token=" + private, Err: errors.New(private)}, "network_failed"},
		{"timeout", &net.DNSError{Name: private, IsTimeout: true}, "dns_failed"},
		{"archive", zip.ErrFormat, "archive_invalid"},
		{"checksum", zip.ErrChecksum, "checksum_mismatch"},
		{"truncated", io.ErrUnexpectedEOF, "data_truncated"},
		{"unknown", errors.New(private), "operation_failed"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			wrapped := fmt.Errorf("%s: %w", private, tc.err)
			classified := classifyFailure(wrapped, "download", "java", "")
			if !errors.Is(classified, tc.err) {
				t.Fatal("diagnostics lost the original error cause")
			}
			event := ErrorDiagnostic(classified, "prepare", "runtime")
			if event.Code != tc.code || event.Stage != "download" || event.Component != "java" {
				t.Fatalf("wrong diagnostic: %+v", event)
			}
			raw, err := json.Marshal(event)
			if err != nil || strings.Contains(string(raw), private) || strings.Contains(classified.Error(), private) {
				t.Fatalf("diagnostic exported private error data: %s / %v", raw, err)
			}
		})
	}
}

func TestDiagnosticExportsZeroAvailableSpace(t *testing.T) {
	raw, err := json.Marshal(Diagnostic{Stage: "storage", Component: "cache", Code: "disk_space", RequiredBytes: 1 << 30})
	if err != nil || !bytes.Contains(raw, []byte(`"availableBytes":0`)) {
		t.Fatalf("full disk lost available-byte observation: %s / %v", raw, err)
	}
}

func TestOfflineDiagnosticsDistinguishFailuresAndRedactMetadata(t *testing.T) {
	forge, java := []byte("Forge payload"), []byte("Java payload")
	m := Manifest{Forge: offlineTestAsset(forge, "tar.gz"), Java: map[string]Asset{
		runtime.GOOS + "-" + runtime.GOARCH: offlineTestAsset(java, "zip"),
	}}
	cases := []struct {
		name string
		code string
	}{
		{"missing", "member_missing"}, {"size", "size_mismatch"}, {"checksum", "checksum_mismatch"},
		{"version", "package_version_mismatch"}, {"private-version", "package_version_mismatch"},
		{"platform", "platform_mismatch"}, {"private-platform", "platform_mismatch"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			metadata := offlineTestMetadata()
			entries := []offlineTestEntry{{name: "forge.tar.gz", data: forge}, {name: "java.zip", data: java}}
			switch tc.name {
			case "missing":
				entries = entries[:1]
			case "size":
				entries[1].data = []byte("short")
			case "checksum":
				entries[1].data = bytes.Repeat([]byte("x"), len(java))
			case "version":
				metadata.PackageID = strings.Repeat("0", 20)
			case "private-version":
				metadata.PackageID = "private/token/deck"
			case "platform":
				metadata.Platform = "windows-386"
			case "private-platform":
				metadata.Platform = "private/token/deck"
			}
			pack := writeOfflineTestPack(t, metadata, entries)
			_, err := importPackArchives(t.Context(), t.TempDir(), pack, m, nil)
			if err == nil {
				t.Fatal("invalid pack was accepted")
			}
			event := ErrorDiagnostic(err, "prepare", "runtime")
			if event.Code != tc.code || event.Stage != "import" {
				t.Fatalf("wrong import failure: %+v", event)
			}
			raw, _ := json.Marshal(event)
			if bytes.Contains(raw, []byte("private")) || bytes.Contains(raw, []byte(pack)) {
				t.Fatalf("untrusted pack metadata escaped: %s", raw)
			}
			if tc.name == "version" && event.ActualPackageID != metadata.PackageID ||
				tc.name == "platform" && event.ActualPlatform != metadata.Platform {
				t.Fatalf("safe mismatched identity was omitted: %+v", event)
			}
		})
	}
	corrupt := filepath.Join(t.TempDir(), "private-pack.hexproof-forgepack")
	if err := os.WriteFile(corrupt, []byte("damaged archive"), 0600); err != nil {
		t.Fatal(err)
	}
	_, err := importPackArchives(t.Context(), t.TempDir(), corrupt, m, nil)
	if event := ErrorDiagnostic(err, "import", "pack"); event.Code != "archive_invalid" {
		t.Fatalf("damaged container was not classified: %+v", event)
	}
}

func TestDownloadDiagnosticsDescribeMirrorFallbackWithoutURLs(t *testing.T) {
	asset, body := downloadFixture()
	m, err := MirrorAssets(Manifest{Forge: asset}, "https://private-mirror.example/private-path")
	if err != nil {
		t.Fatal(err)
	}
	var events []Diagnostic
	ctx := WithDiagnostics(componentContext(t.Context(), "forge"), func(event Diagnostic) { events = append(events, event) })
	attempts := 0
	client := &http.Client{Transport: fixtureTransport(func(r *http.Request) (*http.Response, error) {
		attempts++
		status, data := 503, []byte("private server response")
		if attempts == 2 {
			status, data = 200, body
		}
		return &http.Response{StatusCode: status, ContentLength: int64(len(data)), Header: make(http.Header), Body: io.NopCloser(bytes.NewReader(data))}, nil
	})}
	if _, err := downloadWithClient(ctx, t.TempDir(), m.Forge, nil, client); err != nil {
		t.Fatal(err)
	}
	if attempts != 2 || len(events) != 4 || events[0].Source != "mirror" || events[1].Code != "http_status" ||
		events[1].HTTPStatus != 503 || events[1].Attempt != 1 || events[2].Source != "official" ||
		events[3].Code != "completed" || events[3].Attempt != 2 || events[3].Received != asset.Size {
		t.Fatalf("fallback history was incomplete: %+v", events)
	}
	raw, _ := json.Marshal(events)
	if bytes.Contains(raw, []byte("private")) || bytes.Contains(raw, []byte("https:")) {
		t.Fatalf("download report exposed request/response data: %s", raw)
	}
}

func TestDownloadDiagnosticsKeepRetryAndChecksumRules(t *testing.T) {
	for _, mode := range []string{"not-found", "rate-limit", "checksum"} {
		t.Run(mode, func(t *testing.T) {
			asset, body := downloadFixture()
			var events []Diagnostic
			ctx := WithDiagnostics(t.Context(), func(event Diagnostic) { events = append(events, event) })
			attempts := 0
			client := &http.Client{Transport: fixtureTransport(func(r *http.Request) (*http.Response, error) {
				attempts++
				status, data := 404, body
				if mode == "rate-limit" {
					status = 429
				} else if mode == "checksum" {
					status, data = 200, bytes.Repeat([]byte("x"), len(body))
					if r.Header.Get("Range") != "" {
						t.Fatal("corrupt payload was resumed")
					}
				}
				return &http.Response{StatusCode: status, ContentLength: int64(len(data)), Header: make(http.Header), Body: io.NopCloser(bytes.NewReader(data))}, nil
			})}
			cache := t.TempDir()
			_, err := downloadWithClient(ctx, cache, asset, nil, client)
			wantAttempts, wantCode := 3, "http_status"
			if mode == "not-found" {
				wantAttempts = 1
			} else if mode == "checksum" {
				wantCode = "checksum_mismatch"
			}
			event := ErrorDiagnostic(err, "prepare", "runtime")
			if err == nil || attempts != wantAttempts || event.Code != wantCode || event.Attempt != wantAttempts || event.Total != asset.Size {
				t.Fatalf("retry outcome: %d attempts / %+v / %v", attempts, event, err)
			}
			if mode == "checksum" && event.Received != asset.Size {
				t.Fatalf("checksum failure lost transferred byte count: %+v", event)
			}
			if _, err := os.Stat(filepath.Join(cache, asset.SHA256+".zip")); !errors.Is(err, os.ErrNotExist) {
				t.Fatal("failed download published an archive")
			}
			if len(events) != wantAttempts*2 {
				t.Fatalf("attempt history incomplete: %+v", events)
			}
		})
	}
}
