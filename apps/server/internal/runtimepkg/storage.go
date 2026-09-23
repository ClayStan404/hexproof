// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package runtimepkg

import (
	"context"
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

var ErrDiskSpace = errors.New("at least 1 GiB of free space is required to prepare Forge")

func requireInstallSpace(ctx context.Context, base string) error {
	available, err := freeBytes(base)
	if err != nil {
		return classifyFailure(err, "storage", "cache", "storage_failed")
	}
	// Conservative workspace budget for the pinned Forge + Java archives and
	// extraction. Cached, already verified installations skip this reservation.
	event := Diagnostic{Stage: "storage", Component: "cache", Code: "available", RequiredBytes: 1 << 30}
	// Avoid overflow on unusual filesystems reporting unsigned capacities.
	if available <= 1<<63-1 {
		event.AvailableBytes = int64(available)
	} else {
		event.AvailableBytes = 1<<63 - 1
	}
	ReportDiagnostic(ctx, event)
	if available < 1<<30 {
		event.Code = "disk_space"
		return diagnosticFailure(ErrDiskSpace, event)
	}
	return nil
}

func lockFile(ctx context.Context, path string, exclusive bool) (_ *os.File, resultErr error) {
	defer func() { resultErr = classifyFailure(resultErr, "lock", "cache", "lock_failed") }()
	file, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return nil, err
	}
	waiting := false
	for {
		if err := ctx.Err(); err != nil {
			file.Close()
			return nil, err
		}
		locked, err := tryLockFile(file, exclusive)
		if err != nil || locked {
			if err != nil {
				file.Close()
			}
			return file, err
		}
		if !waiting {
			ReportDiagnostic(ctx, Diagnostic{Stage: "lock", Component: "cache", Code: "waiting"})
			waiting = true
		}
		timer := time.NewTimer(50 * time.Millisecond)
		select {
		case <-ctx.Done():
			timer.Stop()
			file.Close()
			return nil, ctx.Err()
		case <-timer.C:
		}
	}
}

// Use atomically verifies and pins the current generation against cache
// cleanup. Keep the returned lease open until every JVM using it is reaped.
func Use(ctx context.Context, base string) (Installation, io.Closer, error) {
	ReportDiagnostic(ctx, Diagnostic{Stage: "use", Component: "runtime", Code: "started"})
	lock, err := lockFile(ctx, filepath.Join(base, ".cache.lock"), false)
	if err != nil {
		return Installation{}, nil, err
	}
	defer lock.Close()
	installed, err := Check(ctx, base)
	if err != nil {
		return Installation{}, nil, err
	}
	lease, err := lockFile(ctx, filepath.Join(installed.Root, ".use.lock"), false)
	if err != nil {
		return Installation{}, nil, err
	}
	ReportDiagnostic(ctx, Diagnostic{Stage: "use", Component: "runtime", Code: "completed"})
	return installed, lease, nil
}

type CleanupResult struct {
	FreedBytes      int64 `json:"freedBytes"`
	RemovedFiles    int   `json:"removedFiles"`
	KeptGenerations int   `json:"keptGenerations"`
}

var cachedArchive = regexp.MustCompile(`^[a-f0-9]{64}\.(tar\.gz|zip)(\.part)?$`)
var generationName = regexp.MustCompile(`^[a-f0-9]{20}-[a-zA-Z0-9_-]+$`)

// ClearCache removes only reproducible downloads and unused managed
// generations. Current, leased, unrecognized and pre-lease legacy generations
// are retained. It never deletes user decks, settings, or arbitrary paths.
func ClearCache(ctx context.Context, base string) (_ CleanupResult, resultErr error) {
	ReportDiagnostic(ctx, Diagnostic{Stage: "cleanup", Component: "cache", Code: "started"})
	defer func() {
		resultErr = classifyFailure(resultErr, "cleanup", "cache", "storage_failed")
		if resultErr == nil {
			ReportDiagnostic(ctx, Diagnostic{Stage: "cleanup", Component: "cache", Code: "completed"})
		}
	}()
	var result CleanupResult
	if err := os.MkdirAll(base, 0700); err != nil {
		return result, err
	}
	lock, err := lockFile(ctx, filepath.Join(base, ".cache.lock"), true)
	if err != nil {
		return result, err
	}
	defer lock.Close()
	root, err := os.OpenRoot(base)
	if err != nil {
		return result, err
	}
	defer root.Close()
	entries, err := os.ReadDir(base)
	if err != nil {
		return result, err
	}
	current, _ := root.ReadFile(PackageID() + ".current")
	for _, entry := range entries {
		if err := ctx.Err(); err != nil {
			return result, err
		}
		name := entry.Name()
		if name == "downloads" && entry.IsDir() && entry.Type()&os.ModeSymlink == 0 {
			files, err := os.ReadDir(filepath.Join(base, name))
			if err != nil {
				return result, err
			}
			for _, file := range files {
				if !file.Type().IsRegular() || !cachedArchive.MatchString(file.Name()) {
					continue
				}
				info, err := file.Info()
				if err != nil {
					return result, err
				}
				if err := root.Remove(filepath.Join(name, file.Name())); err != nil {
					return result, err
				}
				result.FreedBytes += info.Size()
				result.RemovedFiles++
			}
			continue
		}
		stem := strings.TrimPrefix(name, "prepare-")
		if !entry.IsDir() || entry.Type()&os.ModeSymlink != 0 || !generationName.MatchString(stem) {
			continue
		}
		marker, err := root.ReadFile(filepath.Join(name, ".managed-v1"))
		if err != nil || len(marker) != 20 || !strings.HasPrefix(stem, string(marker)+"-") || name == string(current) {
			result.KeptGenerations++
			continue
		}
		lease, err := root.OpenFile(filepath.Join(name, ".use.lock"), os.O_CREATE|os.O_RDWR, 0600)
		if err != nil {
			return result, err
		}
		locked, err := tryLockFile(lease, true)
		if err != nil || !locked {
			lease.Close()
			if err != nil {
				return result, err
			}
			result.KeptGenerations++
			continue
		}
		var size int64
		var count int
		err = fs.WalkDir(root.FS(), name, func(path string, item fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if err := ctx.Err(); err != nil {
				return err
			}
			if item.Type().IsRegular() {
				info, err := item.Info()
				if err != nil {
					return err
				}
				size += info.Size()
				count++
			}
			return nil
		})
		// The catalog lock prevents a new Use lease here. Windows requires
		// closing our exclusive file handle before deleting the generation.
		lease.Close()
		if err != nil {
			return result, err
		}
		if err := root.RemoveAll(name); err != nil {
			return result, err
		}
		result.FreedBytes += size
		result.RemovedFiles += count
	}
	return result, nil
}
