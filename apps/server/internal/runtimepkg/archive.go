// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package runtimepkg

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"context"
	"errors"
	"io"
	"os"
	"path"
	"path/filepath"
	"strings"
)

const maxExpandedBytes int64 = 2 << 30

func extract(ctx context.Context, archive, format, destination string) (resultErr error) {
	defer func() { resultErr = classifyFailure(resultErr, "extract", diagnosticComponent(ctx), "archive_invalid") }()
	root, err := os.OpenRoot(destination)
	if err != nil {
		return err
	}
	defer root.Close()
	var total int64
	count := 0
	write := func(name string, size int64, mode os.FileMode, reader io.Reader) error {
		total += size
		if !safeName(name) || size < 0 || total > maxExpandedBytes || count > 100000 {
			return failure("unsafe_archive", "invalid archive entry")
		}
		if err := root.MkdirAll(filepath.Dir(filepath.FromSlash(name)), 0700); err != nil {
			return err
		}
		permissions := os.FileMode(0600)
		if mode&0111 != 0 {
			permissions = 0700
		}
		file, err := root.OpenFile(filepath.FromSlash(name), os.O_WRONLY|os.O_CREATE|os.O_EXCL, permissions)
		if err != nil {
			return err
		}
		_, copyErr := io.CopyN(file, &contextReader{ctx: ctx, reader: reader}, size)
		closeErr := file.Close()
		return errors.Join(copyErr, closeErr)
	}
	if format == "zip" {
		archive, err := zip.OpenReader(archive)
		if err != nil {
			return err
		}
		defer archive.Close()
		if len(archive.File) > 100000 {
			return failure("unsafe_archive", "archive has too many entries")
		}
		for _, entry := range archive.File {
			if err := ctx.Err(); err != nil {
				return err
			}
			if !safeName(entry.Name) {
				return failure("unsafe_archive", "unsafe archive path")
			}
			if entry.FileInfo().IsDir() {
				if err := root.MkdirAll(filepath.FromSlash(entry.Name), 0700); err != nil {
					return err
				}
				continue
			}
			if !entry.Mode().IsRegular() || entry.UncompressedSize64 > uint64(maxExpandedBytes) {
				return failure("unsafe_archive", "unsupported zip entry")
			}
			reader, err := entry.Open()
			if err != nil {
				return err
			}
			err = write(entry.Name, int64(entry.UncompressedSize64), entry.Mode(), reader)
			closeErr := reader.Close()
			if err != nil || closeErr != nil {
				return errors.Join(err, closeErr)
			}
		}
		return nil
	}
	if format != "tar.gz" {
		return failure("archive_invalid", "unsupported archive format")
	}
	file, err := os.Open(archive)
	if err != nil {
		return err
	}
	defer file.Close()
	gz, err := gzip.NewReader(file)
	if err != nil {
		return err
	}
	defer gz.Close()
	reader := tar.NewReader(gz)
	var links []*tar.Header
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		header, err := reader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		count++
		if count > 100000 {
			return failure("unsafe_archive", "archive has too many entries")
		}
		if !safeName(header.Name) {
			return failure("unsafe_archive", "unsafe archive path")
		}
		switch header.Typeflag {
		case tar.TypeDir:
			if err := root.MkdirAll(filepath.FromSlash(header.Name), 0700); err != nil {
				return err
			}
		case tar.TypeReg:
			if err := write(header.Name, header.Size, os.FileMode(header.Mode), reader); err != nil {
				return err
			}
		case tar.TypeSymlink, tar.TypeLink:
			links = append(links, header)
			if len(links) > 10000 {
				return failure("unsafe_archive", "too many archive links")
			}
		default:
			return failure("unsafe_archive", "unsupported archive entry")
		}
	}
	// Create links last. os.Root additionally rejects links escaping the private
	// staging tree. Java license links stay intact on Unix distributions.
	for _, link := range links {
		if path.IsAbs(link.Linkname) || strings.ContainsAny(link.Linkname, "\\:\x00") {
			return failure("unsafe_archive", "unsafe archive link")
		}
		resolved := link.Linkname
		if link.Typeflag == tar.TypeSymlink {
			resolved = path.Join(path.Dir(link.Name), link.Linkname)
		}
		if !safeName(resolved) {
			return failure("unsafe_archive", "unsafe archive link")
		}
		if link.Typeflag == tar.TypeSymlink {
			err = root.Symlink(filepath.FromSlash(link.Linkname), filepath.FromSlash(link.Name))
		} else {
			err = root.Link(filepath.FromSlash(resolved), filepath.FromSlash(link.Name))
		}
		if err != nil {
			return err
		}
	}
	return nil
}
