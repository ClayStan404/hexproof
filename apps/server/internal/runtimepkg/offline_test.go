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
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

type offlineTestEntry struct {
	name string
	data []byte
	mode os.FileMode
}

func offlineTestAsset(data []byte, format string) Asset {
	sum := sha256.Sum256(data)
	return Asset{URL: "https://example.invalid/pinned", Format: format,
		Size: int64(len(data)), SHA256: hex.EncodeToString(sum[:])}
}

func writeOfflineTestPack(t *testing.T, metadata offlinePackManifest, entries []offlineTestEntry) string {
	t.Helper()
	file, err := os.Create(filepath.Join(t.TempDir(), "shared pack.hexproof-forgepack"))
	if err != nil {
		t.Fatal(err)
	}
	pack := zip.NewWriter(file)
	raw, err := json.Marshal(metadata)
	if err != nil {
		t.Fatal(err)
	}
	entries = append([]offlineTestEntry{{name: "forge-pack.json", data: raw}}, entries...)
	for _, item := range entries {
		header := &zip.FileHeader{Name: item.name, Method: zip.Store}
		header.SetMode(item.mode | 0600)
		writer, err := pack.CreateHeader(header)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := writer.Write(item.data); err != nil {
			t.Fatal(err)
		}
	}
	if err := errors.Join(pack.Close(), file.Close()); err != nil {
		t.Fatal(err)
	}
	return file.Name()
}

func offlineTestMetadata() offlinePackManifest {
	return offlinePackManifest{SchemaVersion: 1, PackageID: PackageID(), Platform: runtime.GOOS + "-" + runtime.GOARCH}
}

func TestOfflinePackVerifiesEveryArchiveBeforeCaching(t *testing.T) {
	forge, java := []byte("pinned Forge archive"), []byte("pinned Java archive")
	m := Manifest{Forge: offlineTestAsset(forge, "tar.gz"), Java: map[string]Asset{
		runtime.GOOS + "-" + runtime.GOARCH: offlineTestAsset(java, "zip"),
	}}
	for _, mode := range []string{"valid", "corrupt-forge", "corrupt-java", "missing", "duplicate", "traversal",
		"wrong-size", "wrong-version", "wrong-schema", "wrong-platform", "symlink", "cancelled"} {
		t.Run(mode, func(t *testing.T) {
			base := t.TempDir()
			metadata := offlineTestMetadata()
			entries := []offlineTestEntry{{name: "forge.tar.gz", data: forge}, {name: "java.zip", data: java}}
			switch mode {
			case "corrupt-forge":
				entries[0].data = bytes.Repeat([]byte("x"), len(forge))
			case "corrupt-java":
				entries[1].data = bytes.Repeat([]byte("x"), len(java))
			case "missing":
				entries = entries[:1]
			case "duplicate":
				entries[1] = entries[0]
			case "traversal":
				entries[1].name = "../java.zip"
			case "wrong-size":
				entries[1].data = []byte("too small")
			case "wrong-version":
				metadata.PackageID = strings.Repeat("0", 20)
			case "wrong-schema":
				metadata.SchemaVersion = 2
			case "wrong-platform":
				metadata.Platform = "other-platform"
			case "symlink":
				entries[1].mode = os.ModeSymlink
			}
			pack := writeOfflineTestPack(t, metadata, entries)
			before, err := os.ReadFile(pack)
			if err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithCancel(t.Context())
			defer cancel()
			var stages []string
			paths, err := importPackArchives(ctx, base, pack, m, func(stage string, received, total int64) {
				stages = append(stages, stage)
				if mode == "cancelled" && received == total {
					cancel()
				}
			})
			if mode == "valid" {
				if err != nil || len(paths) != 2 || len(stages) == 0 {
					t.Fatalf("import failed: %v / %v / %v", paths, stages, err)
				}
				for name, asset := range map[string]Asset{"forge": m.Forge, "java": m.Java[metadata.Platform]} {
					if err := checkHash(t.Context(), paths[name], asset.SHA256); err != nil {
						t.Fatal(err)
					}
				}
				// Existing verified archives can be imported again without conflicts.
				if _, err := importPackArchives(ctx, base, pack, m, nil); err != nil {
					t.Fatal(err)
				}
			} else {
				if err == nil {
					t.Fatal("invalid or cancelled pack was accepted")
				}
				if mode == "wrong-platform" && !errors.Is(err, ErrPackPlatform) ||
					(mode == "wrong-version" || mode == "wrong-schema") && !errors.Is(err, ErrPackVersion) ||
					mode == "cancelled" && !errors.Is(err, context.Canceled) {
					t.Fatalf("wrong failure category: %v", err)
				}
				files, err := os.ReadDir(base)
				if err != nil || len(files) != 0 {
					t.Fatalf("failed import left staged or cached files: %v / %v", files, err)
				}
			}
			after, err := os.ReadFile(pack)
			if err != nil || !bytes.Equal(before, after) {
				t.Fatal("import modified the shared pack")
			}
		})
	}
}

func offlineTestTar(t *testing.T, entries []offlineTestEntry) []byte {
	t.Helper()
	var data bytes.Buffer
	gz := gzip.NewWriter(&data)
	archive := tar.NewWriter(gz)
	for _, entry := range entries {
		if err := archive.WriteHeader(&tar.Header{Name: entry.name, Size: int64(len(entry.data)), Mode: 0700}); err != nil {
			t.Fatal(err)
		}
		if _, err := archive.Write(entry.data); err != nil {
			t.Fatal(err)
		}
	}
	if err := errors.Join(archive.Close(), gz.Close()); err != nil {
		t.Fatal(err)
	}
	return data.Bytes()
}

func TestOfflinePackInstallsAndRepairsWithoutNetwork(t *testing.T) {
	// These tests are deliberately serial: the public installer reads an embedded
	// pin. Replace it with tiny real archives to exercise the full installation.
	originalManifest, originalTransport := manifestBytes, http.DefaultTransport
	t.Cleanup(func() { manifestBytes, http.DefaultTransport = originalManifest, originalTransport })
	http.DefaultTransport = fixtureTransport(func(*http.Request) (*http.Response, error) {
		t.Error("offline import attempted a network request")
		return nil, errors.New("network is unavailable")
	})
	harness := []byte("fixture harness")
	harnessAsset := offlineTestAsset(harness, "zip")
	files, err := json.Marshal(map[string]any{"files": map[string]any{
		"forge-harness.jar": map[string]any{"sha256": harnessAsset.SHA256},
	}})
	if err != nil {
		t.Fatal(err)
	}
	forge := offlineTestTar(t, []offlineTestEntry{
		{name: "hexproof-forge-runtime/forge-harness.jar", data: harness},
		{name: "hexproof-forge-runtime/RUNTIME-MANIFEST.json", data: files},
	})
	javaName := javaDirectory + "/bin/java"
	if runtime.GOOS == "darwin" {
		javaName = javaDirectory + "/Contents/Home/bin/java"
	} else if runtime.GOOS == "windows" {
		javaName += ".exe"
	}
	java := offlineTestTar(t, []offlineTestEntry{{name: javaName, data: []byte("fixture Java executable")}})
	m := Manifest{SchemaVersion: 1, RuntimeID: "fixture-runtime", Forge: offlineTestAsset(forge, "tar.gz"),
		ForgeManifestSHA256: offlineTestAsset(files, "zip").SHA256,
		Java:                map[string]Asset{runtime.GOOS + "-" + runtime.GOARCH: offlineTestAsset(java, "tar.gz")}}
	manifestBytes, err = json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	entries := []offlineTestEntry{{name: "forge.tar.gz", data: forge}, {name: "java.tar.gz", data: java}}
	pack := writeOfflineTestPack(t, offlineTestMetadata(), entries)
	base := t.TempDir()
	var diagnostics []Diagnostic
	diagnosticCtx := WithDiagnostics(t.Context(), func(event Diagnostic) { diagnostics = append(diagnostics, event) })
	installed, err := ImportPack(diagnosticCtx, base, pack, nil)
	if err != nil {
		t.Fatal(err)
	}
	completed := make(map[string]bool)
	for _, event := range diagnostics {
		if event.Code == "completed" {
			completed[event.Stage+"/"+event.Component] = true
		}
		if event.Stage == "download" {
			t.Fatal("offline import reported an online download")
		}
	}
	for _, stage := range []string{"import/pack", "extract/forge", "extract/java", "verify/runtime", "publish/runtime", "check/runtime"} {
		if !completed[stage] {
			t.Fatalf("successful import omitted stage %s: %+v", stage, diagnostics)
		}
	}
	active, lease, err := Use(t.Context(), base)
	if err != nil || active.Root != installed.Root {
		t.Fatalf("imported installation is not usable: %v", err)
	}
	defer lease.Close()
	if err := os.WriteFile(installed.Java, []byte("damaged"), 0700); err != nil {
		t.Fatal(err)
	}
	repaired, err := ImportPack(t.Context(), base, pack, nil)
	if err != nil || repaired.Root == installed.Root {
		t.Fatalf("repair did not create an immutable generation: %v", err)
	}
	if old, err := os.ReadFile(installed.Java); err != nil || string(old) != "damaged" {
		t.Fatal("repair overwrote a leased generation")
	}
	entries[1].data = bytes.Repeat([]byte("x"), len(java))
	invalid := writeOfflineTestPack(t, offlineTestMetadata(), entries)
	if _, err := ImportPack(t.Context(), base, invalid, nil); err == nil {
		t.Fatal("ready installation bypassed pack validation")
	}
	current, err := Check(t.Context(), base)
	if err != nil || current.Root != repaired.Root {
		t.Fatalf("failed import replaced a working installation: %v", err)
	}
	ctx, cancel := context.WithCancel(t.Context())
	defer cancel()
	_, err = ImportPack(ctx, base, pack, func(stage string, received, total int64) {
		if stage == "importing" && received == total {
			cancel()
		}
	})
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("ignored cancellation: %v", err)
	}
	current, err = Check(t.Context(), base)
	if err != nil || current.Root != repaired.Root {
		t.Fatal("cancellation replaced a working installation")
	}
}

func TestOfflineImportHonorsCacheLockAndRejectsNonPacks(t *testing.T) {
	base := t.TempDir()
	lock, err := lockFile(t.Context(), filepath.Join(base, ".cache.lock"), true)
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Close()
	ctx, cancel := context.WithTimeout(t.Context(), 60*time.Millisecond)
	defer cancel()
	if _, err := ImportPack(ctx, base, "missing.hexproof-forgepack", nil); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("import bypassed preparation/cleanup lock: %v", err)
	}
	lock.Close()
	if _, err := ImportPack(t.Context(), base, "", nil); err == nil {
		t.Fatal("empty pack silently selected online preparation")
	}
	if _, err := ImportPack(t.Context(), base, t.TempDir(), nil); err == nil {
		t.Fatal("directory was accepted as a pack")
	}
}
