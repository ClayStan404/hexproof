// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package runtimepkg

import (
	"archive/zip"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
)

// InstallOverlay verifies the client-bundled adapter before copying it into
// the leased private runtime generation. The expected checksum is compiled
// into the helper by the client build, never selected by a room or remote peer.
// The caller must hold Use's lease until all processes loading the JAR exit.
func InstallOverlay(ctx context.Context, installation Installation, bundled, expected, runtimeID string) (string, error) {
	if len(expected) != 64 || runtimeID == "" || installation.RuntimeID != Pinned().RuntimeID {
		return "", errors.New("missing or incompatible packaged adapter")
	}
	info, err := os.Stat(bundled)
	if err != nil || !info.Mode().IsRegular() || info.Size() <= 0 || info.Size() > 16<<20 {
		return "", errors.New("packaged adapter is missing")
	}
	if err := checkHash(ctx, bundled, expected); err != nil {
		return "", errors.New("packaged adapter checksum mismatch")
	}
	archive, err := zip.OpenReader(bundled)
	if err != nil {
		return "", errors.New("invalid packaged adapter")
	}
	defer archive.Close()
	valid := false
	for _, entry := range archive.File {
		if entry.Name != "META-INF/hexproof-overlay.json" {
			continue
		}
		if entry.UncompressedSize64 > 64<<10 || valid {
			return "", errors.New("invalid packaged adapter metadata")
		}
		stream, err := entry.Open()
		if err != nil {
			return "", err
		}
		raw, readErr := io.ReadAll(io.LimitReader(stream, (64<<10)+1))
		stream.Close()
		var metadata struct {
			SchemaVersion      int    `json:"schemaVersion"`
			RuntimeID          string `json:"runtimeId"`
			BaseRuntimeID      string `json:"baseRuntimeId"`
			BaseManifestSHA256 string `json:"baseManifestSha256"`
		}
		if readErr != nil || len(raw) > 64<<10 || json.Unmarshal(raw, &metadata) != nil ||
			metadata.SchemaVersion != 1 || metadata.RuntimeID != runtimeID ||
			metadata.BaseRuntimeID != installation.RuntimeID || metadata.BaseManifestSHA256 != Pinned().ForgeManifestSHA256 {
			return "", errors.New("packaged adapter identity mismatch")
		}
		valid = true
	}
	if !valid {
		return "", errors.New("packaged adapter metadata is missing")
	}
	destination := filepath.Join(installation.Root, "adapter-"+expected+".jar")
	if checkHash(ctx, destination, expected) == nil {
		return destination, nil
	}
	staged, err := os.CreateTemp(installation.Root, "adapter-")
	if err != nil {
		return "", err
	}
	defer os.Remove(staged.Name())
	defer staged.Close()
	input, err := os.Open(bundled)
	if err != nil {
		return "", err
	}
	defer input.Close()
	_, err = io.Copy(staged, &contextReader{ctx, io.LimitReader(input, (16<<20)+1)})
	if err != nil {
		return "", err
	}
	if err := staged.Close(); err != nil {
		return "", err
	}
	if err := checkHash(ctx, staged.Name(), expected); err != nil {
		return "", err
	}
	if err := os.Rename(staged.Name(), destination); err != nil && checkHash(ctx, destination, expected) != nil {
		return "", err
	}
	return destination, nil
}
