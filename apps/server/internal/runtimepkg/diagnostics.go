// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package runtimepkg

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"io"
	"net"
	"os"
	"regexp"
)

// Diagnostic contains only bounded operational facts. Never add error text,
// filenames, URLs, archive member names, or engine output to this structure.
type Diagnostic struct {
	Stage             string `json:"stage"`
	Component         string `json:"component"`
	Code              string `json:"code"`
	Source            string `json:"source,omitempty"`
	Attempt           int    `json:"attempt,omitempty"`
	HTTPStatus        int    `json:"httpStatus,omitempty"`
	Received          int64  `json:"received,omitempty"`
	Total             int64  `json:"total,omitempty"`
	AvailableBytes    int64  `json:"availableBytes,omitempty"`
	RequiredBytes     int64  `json:"requiredBytes,omitempty"`
	ExpectedPlatform  string `json:"expectedPlatform,omitempty"`
	ActualPlatform    string `json:"actualPlatform,omitempty"`
	ExpectedPackageID string `json:"expectedPackageId,omitempty"`
	ActualPackageID   string `json:"actualPackageId,omitempty"`
	ExitCode          *int   `json:"exitCode,omitempty"`
}

// An exhausted filesystem must export an explicit zero alongside the budget.
func (d Diagnostic) MarshalJSON() ([]byte, error) {
	type fields Diagnostic
	var available *int64
	if d.RequiredBytes > 0 || d.AvailableBytes > 0 {
		available = &d.AvailableBytes
	}
	return json.Marshal(struct {
		fields
		AvailableBytes *int64 `json:"availableBytes,omitempty"`
	}{fields(d), available})
}

type diagnosticSinkKey struct{}
type diagnosticComponentKey struct{}

// WithDiagnostics installs a synchronous sink; it must not block or retain
// mutable process state. Callers sharing a context across goroutines must make
// their sink concurrency safe.
func WithDiagnostics(ctx context.Context, sink func(Diagnostic)) context.Context {
	return context.WithValue(ctx, diagnosticSinkKey{}, sink)
}

func ReportDiagnostic(ctx context.Context, event Diagnostic) {
	if sink, ok := ctx.Value(diagnosticSinkKey{}).(func(Diagnostic)); ok && sink != nil {
		sink(event)
	}
}

func componentContext(ctx context.Context, component string) context.Context {
	return context.WithValue(ctx, diagnosticComponentKey{}, component)
}

func diagnosticComponent(ctx context.Context) string {
	if component, ok := ctx.Value(diagnosticComponentKey{}).(string); ok {
		return component
	}
	return "runtime"
}

type diagnosticError struct {
	event Diagnostic
	cause error
}

func (e *diagnosticError) Error() string { return e.event.Code }
func (e *diagnosticError) Unwrap() error { return e.cause }

func diagnosticFailure(err error, event Diagnostic) error {
	if err == nil {
		return nil
	}
	return &diagnosticError{event: event, cause: err}
}

func failure(code, message string) error {
	return diagnosticFailure(errors.New(message), Diagnostic{Code: code})
}

// ErrorDiagnostic classifies error types, never their text. Existing detailed
// stage/asset information survives outer operation wrappers, as does errors.Is.
func ErrorDiagnostic(err error, stage, component string) Diagnostic {
	event := Diagnostic{Stage: stage, Component: component, Code: "operation_failed"}
	var detailed *diagnosticError
	if errors.As(err, &detailed) {
		event = detailed.event
		if event.Stage == "" {
			event.Stage = stage
		}
		if event.Component == "" {
			event.Component = component
		}
		return event
	}
	var dns *net.DNSError
	var tlsVerification *tls.CertificateVerificationError
	var unknownAuthority x509.UnknownAuthorityError
	var invalidCertificate x509.CertificateInvalidError
	var hostname x509.HostnameError
	var record tls.RecordHeaderError
	var alert tls.AlertError
	var network net.Error
	var pathError *os.PathError
	switch {
	case errors.Is(err, context.Canceled):
		event.Code = "cancelled"
	case errors.Is(err, context.DeadlineExceeded):
		event.Code = "timeout"
	case errors.Is(err, os.ErrPermission):
		event.Code = "permission_denied"
	case errors.Is(err, ErrDiskSpace), isDiskSpaceError(err):
		event.Code = "disk_space"
	case errors.Is(err, os.ErrNotExist):
		event.Code = "file_missing"
	case errors.Is(err, ErrPackVersion):
		event.Code = "package_version_mismatch"
	case errors.Is(err, ErrPackPlatform):
		event.Code = "platform_mismatch"
	case errors.As(err, &dns):
		event.Code = "dns_failed"
	case errors.As(err, &tlsVerification), errors.As(err, &unknownAuthority),
		errors.As(err, &invalidCertificate), errors.As(err, &hostname), errors.As(err, &record), errors.As(err, &alert):
		event.Code = "tls_failed"
	case errors.As(err, &network) && network.Timeout():
		event.Code = "timeout"
	case errors.Is(err, zip.ErrChecksum), errors.Is(err, gzip.ErrChecksum):
		event.Code = "checksum_mismatch"
	case errors.Is(err, zip.ErrFormat), errors.Is(err, tar.ErrHeader), errors.Is(err, gzip.ErrHeader):
		event.Code = "archive_invalid"
	case errors.Is(err, io.ErrUnexpectedEOF), errors.Is(err, io.EOF):
		event.Code = "data_truncated"
	case errors.As(err, &network):
		event.Code = "network_failed"
	case errors.As(err, &pathError):
		event.Code = "storage_failed"
	}
	return event
}

func classifyFailure(err error, stage, component, fallback string) error {
	if err == nil {
		return nil
	}
	event := ErrorDiagnostic(err, stage, component)
	if event.Code == "operation_failed" && fallback != "" {
		event.Code = fallback
	}
	return diagnosticFailure(err, event)
}

var packageIdentity = regexp.MustCompile(`^[a-f0-9]{20}$`)
var platformIdentity = regexp.MustCompile(`^(linux|darwin|windows)-(amd64|arm64|386|arm)$`)

func packIdentityDiagnostic(code string, manifest offlinePackManifest, platform string) Diagnostic {
	event := Diagnostic{Stage: "import", Component: "pack", Code: code,
		ExpectedPackageID: PackageID(), ExpectedPlatform: platform}
	if packageIdentity.MatchString(manifest.PackageID) {
		event.ActualPackageID = manifest.PackageID
	}
	if platformIdentity.MatchString(manifest.Platform) {
		event.ActualPlatform = manifest.Platform
	}
	return event
}
