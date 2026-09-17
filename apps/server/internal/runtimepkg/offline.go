// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package runtimepkg

import (
	"archive/zip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"time"
)

var (
	ErrPackVersion  = errors.New("offline pack does not match this client runtime")
	ErrPackPlatform = errors.New("offline pack is for a different platform")
)

type offlinePackManifest struct {
	SchemaVersion int    `json:"schemaVersion"`
	PackageID     string `json:"packageId"`
	Platform      string `json:"platform"`
}

// The caller holds the cache lock. Pack metadata can identify the payload, but
// only the client's embedded manifest supplies trusted sizes and checksums.
func importPackArchives(ctx context.Context, base, source string, m Manifest, progress Progress) (map[string]string, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	platform := runtime.GOOS + "-" + runtime.GOARCH
	java, ok := m.Java[platform]
	if !ok {
		return nil, ErrPackPlatform
	}
	info, err := os.Stat(source)
	if err != nil {
		return nil, err
	}
	maxJavaSize := java.Size
	for _, asset := range m.Java {
		if asset.Size > maxJavaSize {
			maxJavaSize = asset.Size
		}
	}
	if !info.Mode().IsRegular() || info.Size() > m.Forge.Size+maxJavaSize+(1<<20) {
		return nil, errors.New("invalid offline pack file")
	}
	pack, err := zip.OpenReader(source)
	if err != nil {
		return nil, err
	}
	defer pack.Close()
	if len(pack.File) != 3 {
		return nil, errors.New("offline pack must contain metadata, Forge and Java")
	}
	entries := make(map[string]*zip.File, 3)
	for _, entry := range pack.File {
		if entries[entry.Name] != nil || !entry.Mode().IsRegular() {
			return nil, errors.New("invalid offline pack entry")
		}
		entries[entry.Name] = entry
	}
	metadata := entries["forge-pack.json"]
	if metadata == nil || metadata.UncompressedSize64 > 4096 {
		return nil, errors.New("invalid offline pack metadata")
	}
	reader, err := metadata.Open()
	if err != nil {
		return nil, err
	}
	raw, readErr := io.ReadAll(io.LimitReader(&contextReader{ctx, reader}, 4097))
	closeErr := reader.Close()
	if err := errors.Join(readErr, closeErr); err != nil {
		return nil, err
	}
	var manifest offlinePackManifest
	if len(raw) > 4096 || json.Unmarshal(raw, &manifest) != nil {
		return nil, errors.New("invalid offline pack metadata")
	}
	if manifest.SchemaVersion != 1 || manifest.PackageID != PackageID() {
		return nil, ErrPackVersion
	}
	if manifest.Platform != platform {
		return nil, ErrPackPlatform
	}
	assets := []struct {
		name  string
		asset Asset
	}{{"forge", m.Forge}, {"java", java}}
	for _, item := range assets {
		entry := entries[item.name+"."+item.asset.Format]
		if entry == nil || entry.UncompressedSize64 != uint64(item.asset.Size) {
			return nil, errors.New("offline pack archive is missing or has the wrong size")
		}
	}
	stage, err := os.MkdirTemp(base, "prepare-"+PackageID()+"-")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(stage)
	if err := os.WriteFile(filepath.Join(stage, ".managed-v1"), []byte(PackageID()), 0600); err != nil {
		return nil, err
	}
	total := m.Forge.Size + java.Size
	var received int64
	last := time.Now()
	if progress != nil {
		progress("importing", 0, total)
	}
	for _, item := range assets {
		entry := entries[item.name+"."+item.asset.Format]
		if err := copyPackArchive(ctx, entry, filepath.Join(stage, item.name), item.asset, func(n int) {
			received += int64(n)
			if progress != nil && (received == total || time.Since(last) >= 100*time.Millisecond) {
				progress("importing", received, total)
				last = time.Now()
			}
		}); err != nil {
			return nil, err
		}
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	cache := filepath.Join(base, "downloads")
	if err := os.MkdirAll(cache, 0700); err != nil {
		return nil, err
	}
	paths := make(map[string]string, 2)
	for _, item := range assets {
		path := filepath.Join(cache, item.asset.SHA256+"."+item.asset.Format)
		if err := os.Rename(filepath.Join(stage, item.name), path); err != nil {
			return nil, err
		}
		paths[item.name] = path
	}
	return paths, nil
}

func copyPackArchive(ctx context.Context, entry *zip.File, destination string, asset Asset, progress func(int)) error {
	reader, err := entry.Open()
	if err != nil {
		return err
	}
	defer reader.Close()
	file, err := os.OpenFile(destination, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	defer file.Close()
	hash := sha256.New()
	writer := io.MultiWriter(file, hash)
	bounded := io.LimitReader(&contextReader{ctx, reader}, asset.Size+1)
	buffer := make([]byte, 64<<10)
	var copied int64
	for {
		n, readErr := bounded.Read(buffer)
		copied += int64(n)
		if copied > asset.Size {
			return errors.New("offline pack archive is too large")
		}
		if n > 0 {
			if _, err := writer.Write(buffer[:n]); err != nil {
				return err
			}
			progress(n)
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			return readErr
		}
	}
	if copied != asset.Size || hex.EncodeToString(hash.Sum(nil)) != asset.SHA256 {
		return errors.New("offline pack archive checksum mismatch")
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if err := file.Sync(); err != nil {
		return err
	}
	return file.Close()
}
