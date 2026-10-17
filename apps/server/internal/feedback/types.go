// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package feedback implements the independent, support-private feedback inbox.
package feedback

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"time"
)

const (
	MaxUpload   = 5 << 20
	MaxManifest = 16 << 10
	MaxImage    = 2 << 20
	MaxCrash    = 64 << 10
	MaxHosting  = 512 << 10
)

var (
	ErrNotFound    = errors.New("not_found")
	ErrConflict    = errors.New("content_conflict")
	ErrExpired     = errors.New("content_unavailable")
	ErrCapacity    = errors.New("capacity_unavailable")
	ErrUnavailable = errors.New("service_unavailable")
	ErrInvalid     = errors.New("invalid_content")
	ErrBusy        = errors.New("busy")
)

type Manifest struct {
	SchemaVersion int          `json:"schemaVersion"`
	SubmissionID  string       `json:"submissionId"`
	CreatedAt     string       `json:"createdAt"`
	Category      string       `json:"category"`
	Description   string       `json:"description"`
	ReplyEmail    string       `json:"replyEmail,omitempty"`
	Context       Context      `json:"context"`
	Attachments   []Attachment `json:"attachments"`
}

type Context struct {
	AppVersion     string `json:"appVersion,omitempty"`
	OSFamily       string `json:"osFamily,omitempty"`
	Architecture   string `json:"architecture,omitempty"`
	UILanguage     string `json:"uiLanguage,omitempty"`
	Feature        string `json:"feature,omitempty"`
	GameMode       string `json:"gameMode,omitempty"`
	Format         string `json:"format,omitempty"`
	PriorityMode   string `json:"priorityMode,omitempty"`
	CatalogVersion string `json:"catalogVersion,omitempty"`
	RuntimeID      string `json:"runtimeId,omitempty"`
}

type Attachment struct {
	ID         string `json:"id"`
	Kind       string `json:"kind"`
	MediaType  string `json:"mediaType"`
	ByteLength int64  `json:"byteLength"`
	SHA256     string `json:"sha256"`
	ReportID   string `json:"reportId,omitempty"`
	Revision   int    `json:"revision,omitempty"`
	CapturedAt string `json:"capturedAt,omitempty"`
}

type Blob struct {
	Attachment Attachment `json:"attachment"`
	Bytes      []byte     `json:"bytes"`
}

type Submission struct {
	Manifest Manifest `json:"manifest"`
	Digest   string   `json:"digest"`
	Blobs    []Blob   `json:"blobs"`
}

type Receipt struct {
	SchemaVersion    int    `json:"schemaVersion"`
	SubmissionID     string `json:"submissionId"`
	Receipt          string `json:"receipt"`
	AcceptedAt       string `json:"acceptedAt"`
	ContentExpiresAt string `json:"contentExpiresAt"`
	State            string `json:"state"`
}

type Record struct {
	Receipt    Receipt     `json:"receipt"`
	SecretHash string      `json:"secretHash"`
	Digest     string      `json:"digest"`
	Tombstone  bool        `json:"tombstone,omitempty"`
	Submission *Submission `json:"submission,omitempty"`
}

type Delivery struct {
	State       string    `json:"state"`
	Attempts    int       `json:"attempts"`
	UpdatedAt   time.Time `json:"updatedAt"`
	NextAttempt time.Time `json:"nextAttempt,omitempty"`
	Code        string    `json:"code,omitempty"`
}

func Digest(manifest []byte) string {
	h := sha256.New()
	h.Write([]byte("hexproof-feedback-v1\n"))
	h.Write(manifest)
	return hex.EncodeToString(h.Sum(nil))
}

func hashBytes(raw []byte) string {
	h := sha256.Sum256(raw)
	return hex.EncodeToString(h[:])
}
