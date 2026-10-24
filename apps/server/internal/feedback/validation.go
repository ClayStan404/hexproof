// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"image"
	"image/jpeg"
	"image/png"
	"io"
	"mime"
	"mime/multipart"
	"regexp"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

var idPattern = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)
var hashPattern = regexp.MustCompile(`^[0-9a-f]{64}$`)
var attachmentPattern = regexp.MustCompile(`^[a-z0-9_-]{1,32}$`)
var tokenPattern = regexp.MustCompile(`^[A-Za-z0-9_.$<>:+-]*$`)

func validID(v string) bool   { return idPattern.MatchString(v) }
func validHash(v string) bool { return hashPattern.MatchString(v) }
func oneOf(v string, values ...string) bool {
	for _, x := range values {
		if v == x {
			return true
		}
	}
	return false
}
func token(v string, max int) bool { return len(v) <= max && tokenPattern.MatchString(v) }
func cleanText(v string, max int, multiline bool) bool {
	if len(v) > max || !utf8.ValidString(v) {
		return false
	}
	for _, r := range v {
		if unicode.IsControl(r) && !(multiline && (r == '\n' || r == '\r' || r == '\t')) || unicode.Is(unicode.Cf, r) || r == '\u2028' || r == '\u2029' {
			return false
		}
	}
	return true
}

func validateManifest(raw []byte, id string, now time.Time) (Manifest, error) {
	var m Manifest
	if len(raw) > MaxManifest || decodeClosed(raw, &m) != nil || m.SchemaVersion != 1 || m.SubmissionID != id || !validID(id) || !oneOf(m.Category, "problem", "suggestion", "other") || strings.TrimSpace(m.Description) == "" || !cleanText(m.Description, 8192, true) || (m.ReplyEmail != "" && !validEmail(m.ReplyEmail)) || m.Attachments == nil || len(m.Attachments) > 4 {
		return m, ErrInvalid
	}
	var required map[string]json.RawMessage
	if json.Unmarshal(raw, &required) != nil || required["context"] == nil || string(required["context"]) == "null" {
		return m, ErrInvalid
	}
	created, err := time.Parse(time.RFC3339Nano, m.CreatedAt)
	if err != nil || !strings.HasSuffix(m.CreatedAt, "Z") || len(m.CreatedAt) > 40 || created.Before(now.Add(-7*24*time.Hour)) || created.After(now.Add(10*time.Minute)) {
		return m, ErrInvalid
	}
	c := m.Context
	if !oneOf(c.OSFamily, "", "windows", "macos", "linux", "other") || !oneOf(c.GameMode, "", "manual", "forge") {
		return m, ErrInvalid
	}
	for _, v := range []string{c.AppVersion, c.Architecture, c.UILanguage, c.Feature, c.Format, c.PriorityMode, c.CatalogVersion} {
		if !token(v, 64) {
			return m, ErrInvalid
		}
	}
	if !token(c.RuntimeID, 256) {
		return m, ErrInvalid
	}
	seen := map[string]bool{}
	kinds := map[string]int{}
	for _, a := range m.Attachments {
		if !attachmentPattern.MatchString(a.ID) || seen[a.ID] || !validHash(a.SHA256) || a.ByteLength < 1 {
			return m, ErrInvalid
		}
		seen[a.ID] = true
		kinds[a.Kind]++
		switch a.Kind {
		case "screenshot":
			if kinds[a.Kind] > 2 || !oneOf(a.MediaType, "image/png", "image/jpeg") || a.ByteLength > MaxImage || a.ReportID != "" || a.Revision != 0 || a.CapturedAt != "" {
				return m, ErrInvalid
			}
		case "forge_crash":
			if kinds[a.Kind] > 1 || a.MediaType != "application/json" || a.ByteLength > MaxCrash {
				return m, ErrInvalid
			}
		case "hosting_diagnostics":
			if kinds[a.Kind] > 1 || a.MediaType != "application/json" || a.ByteLength > MaxHosting || a.ReportID != "" || a.Revision != 0 {
				return m, ErrInvalid
			}
		default:
			return m, ErrInvalid
		}
		if a.CapturedAt != "" {
			if _, err := time.Parse(time.RFC3339Nano, a.CapturedAt); err != nil || len(a.CapturedAt) > 40 {
				return m, ErrInvalid
			}
		}
	}
	return m, nil
}

func partType(p *multipart.Part) string {
	v, params, err := mime.ParseMediaType(p.Header.Get("Content-Type"))
	if err != nil || len(params) > 0 {
		return ""
	}
	return v
}
func validPart(p *multipart.Part) bool {
	if p.FileName() != "" || len(p.Header) > 3 {
		return false
	}
	n := 0
	for key, values := range p.Header {
		if !oneOf(strings.ToLower(key), "content-type", "content-disposition") {
			return false
		}
		for _, v := range values {
			n += len(key) + len(v)
		}
		if len(values) != 1 {
			return false
		}
	}
	return n <= 2048
}

func parseSubmission(ctx context.Context, r io.Reader, contentType, id, digest string, now time.Time, decodes chan struct{}) (Submission, error) {
	var sub Submission
	media, params, err := mime.ParseMediaType(contentType)
	if err != nil || media != "multipart/form-data" || len(params) != 1 || len(params["boundary"]) < 1 || len(params["boundary"]) > 70 {
		return sub, ErrInvalid
	}
	mr := multipart.NewReader(r, params["boundary"])
	p, err := mr.NextRawPart()
	if err != nil {
		return sub, ErrInvalid
	}
	if !validPart(p) || p.FormName() != "manifest" || partType(p) != "application/json" {
		return sub, ErrInvalid
	}
	raw, err := readBounded(p, MaxManifest)
	if err != nil || Digest(raw) != digest {
		return sub, ErrInvalid
	}
	m, err := validateManifest(raw, id, now)
	if err != nil {
		return sub, err
	}
	sub = Submission{Manifest: m, Digest: digest, Blobs: []Blob{}}
	declared := map[string]Attachment{}
	for _, a := range m.Attachments {
		declared[a.ID] = a
	}
	for range m.Attachments {
		p, err = mr.NextRawPart()
		if err != nil || !validPart(p) {
			return sub, ErrInvalid
		}
		a, ok := declared[p.FormName()]
		if !ok || partType(p) != a.MediaType {
			return sub, ErrInvalid
		}
		delete(declared, a.ID)
		raw, err = readBounded(p, a.ByteLength)
		if err != nil || int64(len(raw)) != a.ByteLength || hashBytes(raw) != a.SHA256 {
			return sub, ErrInvalid
		}
		var normalized []byte
		switch a.Kind {
		case "screenshot":
			select {
			case decodes <- struct{}{}:
			case <-ctx.Done():
				return sub, ErrUnavailable
			}
			normalized, err = normalizeImage(raw, a.MediaType)
			<-decodes
		case "forge_crash":
			normalized, err = normalizeCrash(raw, a)
		case "hosting_diagnostics":
			normalized, err = normalizeHosting(raw, a)
		}
		if err != nil {
			return sub, ErrInvalid
		}
		a.ByteLength = int64(len(normalized))
		a.SHA256 = hashBytes(normalized)
		sub.Blobs = append(sub.Blobs, Blob{Attachment: a, Bytes: normalized})
	}
	if _, err = mr.NextRawPart(); err != io.EOF {
		return sub, ErrInvalid
	}
	// A chunked request may append an oversized MIME epilogue. Count it too;
	// reaching the final boundary alone does not establish the whole-body cap.
	if _, err = io.Copy(io.Discard, r); err != nil {
		return sub, ErrInvalid
	}
	return sub, nil
}

type limitedBuffer struct {
	bytes.Buffer
	limit int
}

func (b *limitedBuffer) Write(p []byte) (int, error) {
	if b.Len()+len(p) > b.limit {
		return 0, ErrInvalid
	}
	return b.Buffer.Write(p)
}

// decodeImage validates the whole image without changing the approved bytes.
// V1 additionally normalizes its private attachment; V2 publishes the original.
func decodeImage(raw []byte, kind string) (image.Image, error) {
	if len(raw) > MaxImage || !oneOf(kind, "image/png", "image/jpeg") {
		return nil, ErrInvalid
	}
	if kind == "image/png" && !staticPNG(raw) {
		return nil, ErrInvalid
	}
	c, format, err := image.DecodeConfig(bytes.NewReader(raw))
	if err != nil || c.Width < 1 || c.Height < 1 || c.Width > 8192 || c.Height > 8192 || int64(c.Width)*int64(c.Height) > 16_000_000 || (kind == "image/png" && format != "png") || (kind == "image/jpeg" && format != "jpeg") {
		return nil, ErrInvalid
	}
	im, _, err := image.Decode(bytes.NewReader(raw))
	if err != nil {
		return nil, ErrInvalid
	}
	return im, nil
}

func normalizeImage(raw []byte, kind string) ([]byte, error) {
	im, err := decodeImage(raw, kind)
	if err != nil {
		return nil, err
	}
	out := &limitedBuffer{limit: MaxImage}
	if kind == "image/png" {
		err = png.Encode(out, im)
	} else {
		err = jpeg.Encode(out, im, &jpeg.Options{Quality: 90})
	}
	if err != nil {
		return nil, ErrInvalid
	}
	return out.Bytes(), nil
}

func staticPNG(raw []byte) bool {
	if len(raw) < 8 || !bytes.Equal(raw[:8], []byte("\x89PNG\r\n\x1a\n")) {
		return false
	}
	for p := 8; p+12 <= len(raw); {
		n := int64(binary.BigEndian.Uint32(raw[p : p+4]))
		if n > int64(len(raw)-p-12) {
			return false
		}
		kind := string(raw[p+4 : p+8])
		if kind == "acTL" || kind == "fcTL" || kind == "fdAT" {
			return false
		}
		p += int(n) + 12
		if kind == "IEND" {
			return p == len(raw)
		}
	}
	return false
}
