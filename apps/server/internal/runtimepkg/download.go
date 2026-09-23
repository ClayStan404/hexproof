// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package runtimepkg

import (
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func download(ctx context.Context, cache string, asset Asset, progress func(int64, int64)) (string, error) {
	client := &http.Client{Timeout: 30 * time.Minute, CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) > 5 || !safeDownloadURL(req.URL.String()) {
			return failure("invalid_configuration", "unsafe download redirect")
		}
		return nil
	}}
	return downloadWithClient(ctx, cache, asset, progress, client)
}

func safeDownloadURL(value string) bool {
	u, err := url.Parse(value)
	return err == nil && u.Scheme == "https" && u.Hostname() != "" && u.User == nil && u.Fragment == ""
}

// Sources are release metadata or a locally selected mirror, never room input.
// Every source must supply exactly the same pinned size and SHA-256. Range
// support is optional: a full 200 response safely restarts a partial transfer.
func downloadWithClient(ctx context.Context, cache string, asset Asset, progress func(int64, int64), client *http.Client) (_ string, resultErr error) {
	component := diagnosticComponent(ctx)
	defer func() { resultErr = classifyFailure(resultErr, "download", component, "storage_failed") }()
	digest, err := hex.DecodeString(asset.SHA256)
	if err != nil || len(digest) != 32 || strings.ToLower(asset.SHA256) != asset.SHA256 ||
		asset.Size <= 0 || asset.Size > 2<<30 || (asset.Format != "zip" && asset.Format != "tar.gz") || len(asset.Mirrors) > 2 {
		return "", failure("invalid_configuration", "invalid pinned asset")
	}
	sources := append([]string{asset.URL}, asset.Mirrors...)
	for _, source := range sources {
		if !safeDownloadURL(source) {
			return "", failure("invalid_configuration", "invalid pinned asset URL")
		}
	}
	if err := os.MkdirAll(cache, 0700); err != nil {
		return "", err
	}
	path := filepath.Join(cache, asset.SHA256+"."+asset.Format)
	if info, err := os.Lstat(path); err == nil && info.Mode().IsRegular() && info.Size() == asset.Size && checkHash(ctx, path, asset.SHA256) == nil {
		ReportDiagnostic(ctx, Diagnostic{Stage: "download", Component: component, Code: "cache_hit", Source: "cache", Received: asset.Size, Total: asset.Size})
		if progress != nil {
			progress(asset.Size, asset.Size)
		}
		return path, nil
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	partial := path + ".part"
	if info, err := os.Lstat(partial); err == nil && (!info.Mode().IsRegular() || info.Size() > asset.Size) {
		return "", failure("size_mismatch", "invalid partial runtime download")
	}
	file, err := os.OpenFile(partial, os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return "", err
	}
	defer func() {
		_ = file.Close()
		if info, err := os.Stat(partial); err == nil && info.Size() == 0 {
			_ = os.Remove(partial)
		}
	}()
	var transferErr error
	for attempt := 0; attempt < 3; attempt++ {
		if err := ctx.Err(); err != nil {
			return "", err
		}
		info, err := file.Stat()
		if err != nil {
			return "", err
		}
		complete := info.Size() == asset.Size
		source := "official"
		if (attempt%len(sources) == 0 && asset.primaryMirror) || (attempt%len(sources) != 0 && !asset.primaryMirror) {
			source = "mirror"
		}
		event := Diagnostic{Stage: "download", Component: component, Code: "attempt_started", Source: source,
			Attempt: attempt + 1, Received: info.Size(), Total: asset.Size}
		ReportDiagnostic(ctx, event)
		retry := false
		if !complete {
			transferErr, retry = transferRange(ctx, file, info.Size(), asset.Size,
				sources[attempt%len(sources)], progress, client)
			complete = transferErr == nil
		}
		var received int64
		if current, err := file.Stat(); err == nil {
			received = current.Size()
		}
		if complete {
			if err := checkHash(ctx, partial, asset.SHA256); err == nil {
				if err := file.Sync(); err != nil {
					return "", err
				}
				if err := file.Close(); err != nil {
					return "", err
				}
				if err := os.Rename(partial, path); err != nil {
					return "", fmt.Errorf("store verified download: %w", err)
				}
				if progress != nil {
					progress(asset.Size, asset.Size)
				}
				event.Code, event.Received = "completed", asset.Size
				ReportDiagnostic(ctx, event)
				return path, nil
			} else if ctx.Err() != nil {
				return "", ctx.Err()
			} else {
				transferErr = err
			}
			// Corrupt complete data must not become a reusable resume prefix.
			if err := file.Truncate(0); err != nil {
				return "", err
			}
			retry = true
		}
		detail := ErrorDiagnostic(transferErr, "download", component)
		detail.Source, detail.Attempt, detail.Total = source, attempt+1, asset.Size
		detail.Received = received
		transferErr = diagnosticFailure(transferErr, detail)
		ReportDiagnostic(ctx, detail)
		if !retry && len(sources) == 1 || attempt == 2 {
			break
		}
		timer := time.NewTimer(time.Duration(attempt+1) * 200 * time.Millisecond)
		select {
		case <-ctx.Done():
			timer.Stop()
			return "", ctx.Err()
		case <-timer.C:
		}
	}
	return "", transferErr
}

func transferRange(ctx context.Context, file *os.File, offset, total int64, source string,
	progress func(int64, int64), client *http.Client) (resultErr error, retry bool) {
	status := 0
	defer func() {
		if resultErr != nil {
			event := ErrorDiagnostic(resultErr, "download", diagnosticComponent(ctx))
			event.HTTPStatus = status
			resultErr = diagnosticFailure(resultErr, event)
		}
	}()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, source, nil)
	if err != nil {
		return failure("invalid_configuration", "invalid runtime source"), false
	}
	req.Header.Set("User-Agent", "Hexproof-Forge-Host")
	req.Header.Set("Accept-Encoding", "identity")
	if offset > 0 {
		req.Header.Set("Range", fmt.Sprintf("bytes=%d-", offset))
	}
	response, err := client.Do(req)
	if err != nil {
		return classifyFailure(err, "download", diagnosticComponent(ctx), "network_failed"), true
	}
	defer response.Body.Close()
	status = response.StatusCode
	switch response.StatusCode {
	case http.StatusOK:
		if err := file.Truncate(0); err != nil {
			return err, false
		}
		offset = 0
	case http.StatusPartialContent:
		if response.Header.Get("Content-Range") != fmt.Sprintf("bytes %d-%d/%d", offset, total-1, total) {
			return failure("range_mismatch", "runtime resume range mismatch"), false
		}
	default:
		return diagnosticFailure(errors.New("runtime download status mismatch"), Diagnostic{Code: "http_status", HTTPStatus: response.StatusCode}), response.StatusCode == 429 || response.StatusCode >= 500
	}
	if response.Header.Get("Content-Encoding") != "" && response.Header.Get("Content-Encoding") != "identity" {
		return failure("content_encoding", "unexpected runtime content encoding"), false
	}
	if response.ContentLength >= 0 && response.ContentLength != total-offset {
		return failure("size_mismatch", "runtime download size mismatch"), false
	}
	if _, err := file.Seek(offset, io.SeekStart); err != nil {
		return err, false
	}
	if progress != nil {
		progress(offset, total)
	}
	reader := io.LimitReader(response.Body, total-offset+1)
	buffer := make([]byte, 64<<10)
	last := time.Now()
	for {
		if err := ctx.Err(); err != nil {
			return err, false
		}
		n, readErr := reader.Read(buffer)
		if n > 0 {
			offset += int64(n)
			if offset > total {
				_ = file.Truncate(0)
				return failure("size_mismatch", "runtime download too large"), false
			}
			if _, err := file.Write(buffer[:n]); err != nil {
				return err, false
			}
			if progress != nil && time.Since(last) >= 100*time.Millisecond {
				progress(offset, total)
				last = time.Now()
			}
		}
		if readErr == io.EOF && offset == total {
			return nil, false
		}
		if readErr != nil {
			return classifyFailure(readErr, "download", diagnosticComponent(ctx), "download_interrupted"), true
		}
	}
}

// MirrorAssets optionally maps pinned artifacts to a user-selected HTTPS
// directory. Names are content addressed: <sha256>.<format>. The official URL
// remains a fallback and all integrity checks still apply.
func MirrorAssets(m Manifest, directory string) (Manifest, error) {
	if directory == "" {
		return m, nil
	}
	u, err := url.Parse(directory)
	if err != nil || !safeDownloadURL(directory) || u.RawQuery != "" {
		return Manifest{}, failure("invalid_configuration", "invalid runtime mirror directory")
	}
	apply := func(asset Asset) Asset {
		asset.primaryMirror = true
		asset.Mirrors = []string{asset.URL}
		asset.URL = strings.TrimRight(directory, "/") + "/" + asset.SHA256 + "." + asset.Format
		return asset
	}
	m.Forge = apply(m.Forge)
	platforms := make(map[string]Asset, len(m.Java))
	for platform, asset := range m.Java {
		platforms[platform] = apply(asset)
	}
	m.Java = platforms
	return m, nil
}
