// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package runtimepkg installs the immutable optional desktop engine payload.
// Downloads never select commands or versions supplied by a room/server.
package runtimepkg

import (
	"context"
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

//go:embed manifest.json
var manifestBytes []byte

type Asset struct {
	primaryMirror bool
	Mirrors       []string `json:"mirrors,omitempty"`
	URL           string   `json:"url"`
	Size          int64    `json:"size"`
	SHA256        string   `json:"sha256"`
	Format        string   `json:"format"`
}
type Manifest struct {
	SchemaVersion       int              `json:"schemaVersion"`
	RuntimeID           string           `json:"runtimeId"`
	ForgeManifestSHA256 string           `json:"forgeManifestSha256"`
	Forge               Asset            `json:"forge"`
	Java                map[string]Asset `json:"java"`
}
type Installation struct {
	Root      string `json:"root"`
	Java      string `json:"java"`
	Harness   string `json:"harness"`
	ForgeHome string `json:"forgeHome"`
	RuntimeID string `json:"runtimeId"`
}
type Progress func(stage string, received, total int64)

func Pinned() Manifest {
	var m Manifest
	if err := json.Unmarshal(manifestBytes, &m); err != nil {
		panic(err)
	}
	return m
}
func PackageID() string { sum := sha256.Sum256(manifestBytes); return hex.EncodeToString(sum[:])[:20] }

func Check(ctx context.Context, base string) (_ Installation, resultErr error) {
	ReportDiagnostic(ctx, Diagnostic{Stage: "check", Component: "runtime", Code: "started"})
	defer func() {
		resultErr = classifyFailure(resultErr, "check", "runtime", "integrity_invalid")
		if resultErr == nil {
			ReportDiagnostic(ctx, Diagnostic{Stage: "check", Component: "runtime", Code: "completed"})
		}
	}()
	name, err := os.ReadFile(filepath.Join(base, PackageID()+".current"))
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return Installation{}, diagnosticFailure(err, Diagnostic{Code: "runtime_not_prepared"})
		}
		return Installation{}, err
	}
	if !safeName(string(name)) || strings.Contains(string(name), "/") || !strings.HasPrefix(string(name), PackageID()+"-") {
		return Installation{}, failure("integrity_invalid", "invalid runtime pointer")
	}
	root := filepath.Join(base, string(name))
	marker, err := os.ReadFile(filepath.Join(root, "complete"))
	if err != nil {
		return Installation{}, err
	}
	if string(marker) != PackageID() {
		return Installation{}, failure("integrity_invalid", "invalid runtime marker")
	}
	return validate(ctx, root, Pinned())
}

func Prepare(ctx context.Context, base string, progress Progress) (Installation, error) {
	return PrepareWithMirror(ctx, base, "", progress)
}

func PrepareWithMirror(ctx context.Context, base, mirror string, progress Progress) (Installation, error) {
	return prepare(ctx, base, mirror, "", progress)
}

// ImportPack prepares the pinned runtime entirely from a local offline pack.
// It never falls back to a download, even when an archive is missing or damaged.
func ImportPack(ctx context.Context, base, pack string, progress Progress) (Installation, error) {
	if pack == "" {
		return Installation{}, diagnosticFailure(os.ErrNotExist, Diagnostic{Stage: "import", Component: "pack", Code: "file_missing"})
	}
	return prepare(ctx, base, "", pack, progress)
}

func prepare(ctx context.Context, base, mirror, pack string, progress Progress) (_ Installation, resultErr error) {
	diagnosticStage := "storage"
	defer func() { resultErr = classifyFailure(resultErr, diagnosticStage, "runtime", "storage_failed") }()
	ReportDiagnostic(ctx, Diagnostic{Stage: diagnosticStage, Component: "cache", Code: "started"})
	if err := os.MkdirAll(base, 0700); err != nil {
		return Installation{}, err
	}
	lock, err := lockFile(ctx, filepath.Join(base, ".cache.lock"), true)
	if err != nil {
		return Installation{}, err
	}
	defer lock.Close()
	m, err := MirrorAssets(Pinned(), mirror)
	if err != nil {
		return Installation{}, err
	}
	var archives map[string]string
	if pack != "" {
		if err := requireInstallSpace(ctx, base); err != nil {
			return Installation{}, err
		}
		archives, err = importPackArchives(ctx, base, pack, m, progress)
		if err != nil {
			return Installation{}, err
		}
	}
	if installed, err := Check(ctx, base); err == nil {
		return installed, nil
	}
	java, ok := m.Java[runtime.GOOS+"-"+runtime.GOARCH]
	if !ok {
		return Installation{}, failure("unsupported_platform", "unsupported hosting platform")
	}
	if err := requireInstallSpace(ctx, base); err != nil {
		return Installation{}, err
	}
	stage, err := os.MkdirTemp(base, "prepare-"+PackageID()+"-")
	if err != nil {
		return Installation{}, err
	}
	defer os.RemoveAll(stage)
	if err := os.WriteFile(filepath.Join(stage, ".managed-v1"), []byte(PackageID()), 0600); err != nil {
		return Installation{}, err
	}
	cache := filepath.Join(base, "downloads")
	for _, item := range []struct {
		name  string
		asset Asset
	}{{"forge", m.Forge}, {"java", java}} {
		itemCtx := componentContext(ctx, item.name)
		archive := archives[item.name]
		if pack == "" {
			archive, err = download(itemCtx, cache, item.asset, func(received, total int64) {
				if progress != nil {
					progress(item.name, received, total)
				}
			})
			if err != nil {
				return Installation{}, err
			}
		}
		if progress != nil {
			progress("extracting", 0, 0)
		}
		ReportDiagnostic(ctx, Diagnostic{Stage: "extract", Component: item.name, Code: "started"})
		if err := extract(itemCtx, archive, item.asset.Format, stage); err != nil {
			return Installation{}, err
		}
		ReportDiagnostic(ctx, Diagnostic{Stage: "extract", Component: item.name, Code: "completed"})
	}
	if progress != nil {
		progress("verifying", 0, 0)
	}
	ReportDiagnostic(ctx, Diagnostic{Stage: "verify", Component: "runtime", Code: "started"})
	if err := writeJavaIntegrity(ctx, stage); err != nil {
		return Installation{}, classifyFailure(err, "verify", "java", "integrity_invalid")
	}
	if _, err := validate(ctx, stage, m); err != nil {
		return Installation{}, classifyFailure(err, "verify", "runtime", "integrity_invalid")
	}
	ReportDiagnostic(ctx, Diagnostic{Stage: "verify", Component: "runtime", Code: "completed"})
	diagnosticStage = "publish"
	ReportDiagnostic(ctx, Diagnostic{Stage: "publish", Component: "runtime", Code: "started"})
	if err := os.WriteFile(filepath.Join(stage, "complete"), []byte(PackageID()), 0600); err != nil {
		return Installation{}, err
	}
	// Repair publishes a new immutable generation. A running helper keeps its
	// old absolute paths, including on Windows where loaded files cannot move.
	name := strings.TrimPrefix(filepath.Base(stage), "prepare-")
	destination := filepath.Join(base, name)
	if err := os.Rename(stage, destination); err != nil {
		return Installation{}, err
	}
	pointer, err := os.CreateTemp(base, "current-")
	if err != nil {
		return Installation{}, err
	}
	defer os.Remove(pointer.Name())
	_, writeErr := pointer.WriteString(name)
	closeErr := pointer.Close()
	if err := errors.Join(writeErr, closeErr); err != nil {
		return Installation{}, err
	}
	if err := os.Rename(pointer.Name(), filepath.Join(base, PackageID()+".current")); err != nil {
		return Installation{}, err
	}
	ReportDiagnostic(ctx, Diagnostic{Stage: "publish", Component: "runtime", Code: "completed"})

	return Check(ctx, base)
}

func validate(ctx context.Context, root string, m Manifest) (_ Installation, resultErr error) {
	component := "forge"
	defer func() { resultErr = classifyFailure(resultErr, "verify", component, "integrity_invalid") }()
	forgeRoot := filepath.Join(root, "hexproof-forge-runtime")
	manifestFile := filepath.Join(forgeRoot, "RUNTIME-MANIFEST.json")
	if err := checkHash(ctx, manifestFile, m.ForgeManifestSHA256); err != nil {
		return Installation{}, err
	}
	data, err := os.ReadFile(manifestFile)
	if err != nil {
		return Installation{}, err
	}
	var files struct {
		Files map[string]struct {
			SHA256 string `json:"sha256"`
		} `json:"files"`
	}
	if json.Unmarshal(data, &files) != nil || len(files.Files) == 0 {
		return Installation{}, failure("metadata_invalid", "invalid runtime manifest")
	}
	for name, entry := range files.Files {
		if !safeName(name) {
			return Installation{}, failure("unsafe_archive", "invalid runtime path")
		}
		if err := checkHash(ctx, filepath.Join(forgeRoot, filepath.FromSlash(name)), entry.SHA256); err != nil {
			return Installation{}, err
		}
	}
	component = "java"
	if err := verifyJavaIntegrity(ctx, root); err != nil {
		return Installation{}, err
	}
	javaRoot := filepath.Join(root, javaDirectory)
	if runtime.GOOS == "darwin" {
		javaRoot = filepath.Join(javaRoot, "Contents", "Home")
	}
	executable := "java"
	if runtime.GOOS == "windows" {
		executable += ".exe"
	}
	java := filepath.Join(javaRoot, "bin", executable)
	info, err := os.Stat(java)
	if err != nil {
		return Installation{}, err
	}
	if !info.Mode().IsRegular() {
		return Installation{}, failure("file_missing", "Java runtime is missing")
	}
	return Installation{Root: root, Java: java, Harness: filepath.Join(forgeRoot, "forge-harness.jar"), ForgeHome: filepath.Join(forgeRoot, "forge-gui"), RuntimeID: m.RuntimeID}, nil
}

func checkHash(ctx context.Context, name, expected string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	file, err := os.Open(name)
	if err != nil {
		return err
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, &contextReader{ctx: ctx, reader: file}); err != nil {
		return err
	}
	if hex.EncodeToString(hash.Sum(nil)) != expected {
		return failure("checksum_mismatch", "runtime checksum mismatch")
	}
	return nil
}

type contextReader struct {
	ctx    context.Context
	reader io.Reader
}

func (r *contextReader) Read(p []byte) (int, error) {
	if err := r.ctx.Err(); err != nil {
		return 0, err
	}
	return r.reader.Read(p)
}

func safeName(name string) bool {
	return name != "" && !strings.ContainsAny(name, "\\:\x00") && !strings.HasPrefix(name, "/") && filepath.IsLocal(filepath.FromSlash(name))
}
