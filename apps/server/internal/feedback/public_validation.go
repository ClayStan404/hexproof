// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"io"
	"mime"
	"mime/multipart"
	"regexp"
	"sort"
	"time"
)

// Conservative known credential signatures; screenshots cannot be guaranteed anonymous.
var publicCredentialPattern = regexp.MustCompile(`(?i)(-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})|(?:authorization\s*:\s*(?:bearer|feedback)\s+\S{16,})|(?:password|api[_-]?key|access[_-]?token)\s*[:=]\s*[^\s]{8,})`)

func validatePublicManifest(raw []byte, id string, now time.Time, c PublicConfig) (PublicManifest, error) {
	return validatePublicManifestFor(raw, id, "", now, c)
}
func validatePublicManifestFor(raw []byte, id, parent string, now time.Time, c PublicConfig) (PublicManifest, error) {
	var m PublicManifest
	if len(raw) > MaxManifest || decodeClosed(raw, &m) != nil || m.SchemaVersion != 2 || publicJSONCredentials(raw) || m.Disclosure.Revision != c.NoticeRevision || m.Disclosure.SHA256 != hashBytes([]byte(c.NoticeText)) || m.Disclosure.Repository != c.Repository || m.Disclosure.ProviderPolicyRevision != c.ProviderPolicyRevision {
		return m, ErrInvalid
	}
	if m.ParentSubmissionID != parent || parent == "" && (m.QuestionID != "" || m.QuestionRevision != 0) || parent != "" && (!validID(parent) || m.QuestionID != "" && (!validID(m.QuestionID) || m.QuestionRevision < 1) || m.QuestionID == "" && m.QuestionRevision != 0) {
		return m, ErrInvalid
	}
	// Reuse the same diagnostic/category/date bounds without adding a private lane.
	old := Manifest{SchemaVersion: 1, SubmissionID: m.SubmissionID, CreatedAt: m.CreatedAt, Category: m.Category, Description: m.Description, Context: m.Context, Attachments: m.Attachments}
	legacy, _ := json.Marshal(old)
	if _, err := validateManifest(legacy, id, now); err != nil {
		return m, err
	}
	var fields map[string]json.RawMessage
	if json.Unmarshal(raw, &fields) != nil || parent == "" && (fields["parentSubmissionId"] != nil || fields["questionId"] != nil || fields["questionRevision"] != nil) || fields["context"] == nil || string(fields["context"]) == "null" {
		return m, ErrInvalid
	}
	return m, nil
}

func parsePublicSubmission(ctx context.Context, r io.Reader, contentType, id, digest string, now time.Time, c PublicConfig, decodes chan struct{}) (PublicSubmission, error) {
	return parsePublicSubmissionFor(ctx, r, contentType, id, "", digest, now, c, decodes)
}
func parsePublicSubmissionFor(ctx context.Context, r io.Reader, contentType, id, parent, digest string, now time.Time, c PublicConfig, decodes chan struct{}) (PublicSubmission, error) {
	var sub PublicSubmission
	media, params, err := mime.ParseMediaType(contentType)
	if err != nil || media != "multipart/form-data" || len(params) != 1 || len(params["boundary"]) < 1 || len(params["boundary"]) > 70 {
		return sub, ErrInvalid
	}
	mr := multipart.NewReader(r, params["boundary"])
	p, err := mr.NextRawPart()
	if err != nil || !validPart(p) || p.FormName() != "manifest" || partType(p) != "application/json" {
		return sub, ErrInvalid
	}
	raw, err := readBounded(p, MaxManifest)
	hash := PublicDigest(raw)
	if parent != "" {
		hash = PublicReplyDigest(raw)
	}
	if err != nil || hash != digest {
		return sub, ErrInvalid
	}
	m, err := validatePublicManifestFor(raw, id, parent, now, c)
	if err != nil {
		return sub, err
	}
	sub = PublicSubmission{Target: c.target(), Manifest: m, ManifestBytes: raw, Digest: digest, Blobs: []Blob{}}
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
		switch a.Kind {
		case "screenshot":
			// Public previews authorize these exact bytes. Decode for validation but
			// never publish a second encoding that the submitter did not inspect.
			if !publicImage(raw, a.MediaType) {
				return sub, ErrInvalid
			}
			select {
			case decodes <- struct{}{}:
			case <-ctx.Done():
				return sub, ErrUnavailable
			}
			_, err = normalizeImage(raw, a.MediaType)
			<-decodes
		case "forge_crash":
			_, err = normalizeCrash(raw, a)
		case "hosting_diagnostics":
			_, err = normalizeHosting(raw, a)
		}
		if err != nil || a.MediaType == "application/json" && publicJSONCredentials(raw) {
			return sub, ErrInvalid
		}
		sub.Blobs = append(sub.Blobs, Blob{Attachment: a, Bytes: raw})
	}
	if _, err = mr.NextRawPart(); err != io.EOF {
		return sub, ErrInvalid
	}
	if _, err = io.Copy(io.Discard, r); err != nil {
		return sub, ErrInvalid
	}
	order := map[string]int{}
	for i, a := range m.Attachments {
		order[a.ID] = i
	}
	sort.Slice(sub.Blobs, func(i, j int) bool { return order[sub.Blobs[i].Attachment.ID] < order[sub.Blobs[j].Attachment.ID] })
	return sub, nil
}

func publicImage(raw []byte, kind string) bool {
	if kind != "image/png" || !staticPNG(raw) {
		return false
	}
	for p := 8; p+12 <= len(raw); {
		n := int(binary.BigEndian.Uint32(raw[p : p+4]))
		if !oneOf(string(raw[p+4:p+8]), "IHDR", "PLTE", "IDAT", "IEND", "tRNS", "pHYs") {
			return false
		}
		p += n + 12
	}
	return true
}

// Decode before screening so JSON escapes cannot hide a known credential.
func publicJSONCredentials(raw []byte) bool {
	var value any
	if json.Unmarshal(raw, &value) != nil {
		return true
	}
	return publicValueCredentials(value)
}
func publicValueCredentials(value any) bool {
	switch v := value.(type) {
	case string:
		return publicCredentialPattern.MatchString(v)
	case map[string]any:
		for _, item := range v {
			if publicValueCredentials(item) {
				return true
			}
		}
	case []any:
		for _, item := range v {
			if publicValueCredentials(item) {
				return true
			}
		}
	}
	return false
}
