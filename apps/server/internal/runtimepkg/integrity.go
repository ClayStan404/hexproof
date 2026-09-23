// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package runtimepkg

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
)

const javaDirectory = "jdk-21.0.12.1+1-jre"

type integrityEntry struct {
	SHA256 string `json:"sha256,omitempty"`
	Link   string `json:"link,omitempty"`
}

// Recorded only after the pinned distribution archive was authenticated. This
// detects cache damage; it is not an attestation against a malicious owner.
func writeJavaIntegrity(ctx context.Context, root string) error {
	files := map[string]integrityEntry{}
	java := filepath.Join(root, javaDirectory)
	err := filepath.WalkDir(java, func(name string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		relative, err := filepath.Rel(java, name)
		if err != nil {
			return err
		}
		var record integrityEntry
		if entry.Type()&os.ModeSymlink != 0 {
			record.Link, err = os.Readlink(name)
		} else {
			file, openErr := os.Open(name)
			if openErr != nil {
				return openErr
			}
			hash := sha256.New()
			_, err = io.Copy(hash, &contextReader{ctx, file})
			err = errors.Join(err, file.Close())
			record.SHA256 = hex.EncodeToString(hash.Sum(nil))
		}
		if err != nil {
			return err
		}
		files[filepath.ToSlash(relative)] = record
		return nil
	})
	if err != nil {
		return err
	}
	raw, err := json.Marshal(files)
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(root, "JAVA-CHECKSUMS.json"), raw, 0600)
}

func verifyJavaIntegrity(ctx context.Context, root string) error {
	raw, err := os.ReadFile(filepath.Join(root, "JAVA-CHECKSUMS.json"))
	if err != nil {
		return err
	}
	var files map[string]integrityEntry
	if len(raw) > 4<<20 || json.Unmarshal(raw, &files) != nil || len(files) == 0 {
		return failure("metadata_invalid", "invalid Java integrity record")
	}
	for relative, record := range files {
		if !safeName(relative) {
			return failure("unsafe_archive", "invalid Java path")
		}
		name := filepath.Join(root, javaDirectory, filepath.FromSlash(relative))
		if record.Link != "" {
			actual, err := os.Readlink(name)
			if err != nil {
				return err
			}
			if actual != record.Link {
				return failure("checksum_mismatch", "Java link checksum mismatch")
			}
		} else if err := checkHash(ctx, name, record.SHA256); err != nil {
			return err
		}
	}
	return nil
}
