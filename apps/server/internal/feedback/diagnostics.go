// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"bytes"
	"encoding/json"
	"math"
	"regexp"
	"strings"
	"time"

	"hexproof/server/internal/protocol"
)

var reportIDPattern = regexp.MustCompile(`^(?:[0-9a-f]{32}|[0-9a-f]{64})$`)

func normalizeCrash(raw []byte, a Attachment) ([]byte, error) {
	var r protocol.RulesCrashReport
	if len(raw) > MaxCrash || decodeClosed(raw, &r) != nil || r.SchemaVersion != 1 || r.FingerprintVersion != 1 || !reportIDPattern.MatchString(r.ReportID) || !validHash(r.Fingerprint) || r.Revision < 1 || r.Revision > 2 || !oneOf(r.CollectionState, "collecting", "complete", "partial") || (r.Revision == 2 && r.CollectionState == "collecting") {
		return nil, ErrInvalid
	}
	if !utcTime(r.OccurredAt) || a.ReportID != "" && a.ReportID != r.ReportID || a.Revision != 0 && a.Revision != r.Revision || a.CapturedAt != "" && a.CapturedAt != r.OccurredAt {
		return nil, ErrInvalid
	}
	if r.Versions.Adapter < 0 || r.Versions.Adapter > 1000000 || r.Environment.Participants < 1 || r.Environment.Participants > 16 || r.Environment.GameNumber < 0 || r.Environment.GameNumber > 1000000 {
		return nil, ErrInvalid
	}
	if !validCrashFailure(r.Failure) || (r.RecoveryFailure != nil && !validCrashFailure(*r.RecoveryFailure)) {
		return nil, ErrInvalid
	}
	c := r.Context
	if !oneOf(c.Attribution, "execution_site", "resolution_context", "recent_context", "unknown") || c.Turn < 0 || c.Turn > 10000000 || len(c.Spans) > 8 || len(c.Sources) > 4 || len(c.Events) > 32 || (c.ActiveSeat != nil && (*c.ActiveSeat < -1 || *c.ActiveSeat > 15)) {
		return nil, ErrInvalid
	}
	for _, s := range c.Sources {
		if !oneOf(s.Zone, "battlefield", "graveyard", "exile", "command", "stack", "ante") || !cleanText(s.Identity.Name, 1024, false) || !cleanText(s.Identity.SetCode, 128, false) || !cleanText(s.Identity.CollectorNumber, 256, false) {
			return nil, ErrInvalid
		}
	}
	for _, e := range c.Events {
		if !oneOf(e.Origin, "native", "hub") || e.Seat != nil && (*e.Seat < -1 || *e.Seat > 15) {
			return nil, ErrInvalid
		}
	}
	if len(r.Completeness.Missing) > 16 {
		return nil, ErrInvalid
	}
	// Match the native client's normalized diagnostic projection: symbol-like
	// fields are bounded tokens; only card display names are ordinary text.
	var tree any
	d := json.NewDecoder(bytes.NewReader(raw))
	d.UseNumber()
	if d.Decode(&tree) != nil || !diagnosticScalars(tree, "") {
		return nil, ErrInvalid
	}
	return json.Marshal(r)
}

func validCrashFailure(f protocol.RulesCrashFailure) bool {
	if !oneOf(f.Kind, "engine_exception", "resource_exhausted", "execution_timeout", "protocol_failure", "process_exit", "host_connection_lost") || len(f.Causes) > 4 {
		return false
	}
	frames := 0
	for _, c := range f.Causes {
		frames += len(c.Frames)
		for _, f := range c.Frames {
			if f.Line < -2 || f.Line > 10000000 {
				return false
			}
		}
	}
	return frames <= 32
}

func diagnosticScalars(value any, key string) bool {
	switch v := value.(type) {
	case map[string]any:
		for k, x := range v {
			if !diagnosticScalars(x, k) {
				return false
			}
		}
	case []any:
		for _, x := range v {
			if !diagnosticScalars(x, key) {
				return false
			}
		}
	case string:
		switch key {
		case "occurredAt":
			return utcTime(v)
		case "name":
			return cleanText(v, 1024, false)
		case "setCode":
			return cleanText(v, 128, false)
		case "collectorNumber":
			return cleanText(v, 256, false)
		default:
			return token(v, 256)
		}
	case json.Number:
		n, err := v.Int64()
		return err == nil && n >= 0 && n <= 9007199254740991 || err == nil && oneOf(key, "exitCode", "line", "activeSeat", "seat") && n >= -2147483648 && n <= 2147483647
	case bool:
	case nil:
		return false
	default:
		return false
	}
	return true
}

func utcTime(s string) bool {
	_, err := time.Parse(time.RFC3339Nano, s)
	return err == nil && len(s) <= 40 && strings.HasSuffix(s, "Z")
}

// Hosting exports have an independent schema. Its allowlist deliberately
// excludes helper configuration, paths, endpoints, arbitrary logs and grants.
var hostingRootFields = fieldSet("schemaVersion applicationVersion helperVersion runtimeId ready hosting state recentStates transport directDecisions relayFallbacks events historyPersistence exportedAt operatingSystem kernelType operatingSystemVersion kernelVersion qtVersion architecture availableBytes storageTotalBytes")
var hostingEventFields = fieldSet("operationId parentOperationId operation kind timestamp elapsedMs applicationVersion helperVersion runtimeId stage component source code state outcome expectedPlatform actualPlatform expectedPackageId actualPackageId received total availableBytes requiredBytes attempt httpStatus exitCode")
var hostingNumberFields = fieldSet("schemaVersion directDecisions relayFallbacks availableBytes storageTotalBytes elapsedMs received total requiredBytes attempt httpStatus exitCode")
var hostingUUID = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)
var hostingVersion = regexp.MustCompile(`^[0-9]{1,5}\.[0-9]{1,5}\.[0-9]{1,5}(?:-(?:alpha|beta|rc)\.[0-9]{1,5})?(?:\+[0-9a-f]{7,40})?$`)
var runtimePattern = regexp.MustCompile(`^[0-9a-f]{40}-adapter[0-9]{1,5}-[0-9a-f]{64}$`)
var numericVersion = regexp.MustCompile(`^[0-9]+(?:\.[0-9]+){0,3}$`)

func fieldSet(s string) map[string]bool {
	m := map[string]bool{}
	for _, v := range strings.Fields(s) {
		m[v] = true
	}
	return m
}

func normalizeHosting(raw []byte, a Attachment) ([]byte, error) {
	var unused any
	if len(raw) > MaxHosting || decodeClosed(raw, &unused) != nil {
		return nil, ErrInvalid
	}
	var root map[string]any
	d := json.NewDecoder(bytes.NewReader(raw))
	d.UseNumber()
	if d.Decode(&root) != nil || root == nil {
		return nil, ErrInvalid
	}
	if n, ok := root["schemaVersion"].(json.Number); !ok || n.String() != "2" {
		return nil, ErrInvalid
	}
	if !validateHostingObject(root, false) {
		return nil, ErrInvalid
	}
	if a.CapturedAt != "" && root["exportedAt"] != a.CapturedAt {
		return nil, ErrInvalid
	}
	return json.Marshal(root)
}

func validateHostingObject(object map[string]any, event bool) bool {
	fields := hostingRootFields
	if event {
		fields = hostingEventFields
	}
	for key, value := range object {
		if !fields[key] {
			return false
		}
		switch key {
		case "events":
			items, ok := value.([]any)
			if !ok || len(items) > 256 {
				return false
			}
			for _, item := range items {
				obj, ok := item.(map[string]any)
				if !ok || !validateHostingObject(obj, true) {
					return false
				}
			}
		case "recentStates":
			items, ok := value.([]any)
			if !ok || len(items) > 256 {
				return false
			}
			for _, item := range items {
				s, ok := item.(string)
				if !ok || !hostingText("state", s) {
					return false
				}
			}
		case "ready", "hosting":
			if _, ok := value.(bool); !ok {
				return false
			}
		default:
			if hostingNumberFields[key] {
				number, ok := value.(json.Number)
				if !ok {
					return false
				}
				n, err := number.Int64()
				min := int64(0)
				max := int64(9007199254740991)
				switch key {
				case "exitCode":
					min = math.MinInt32
					max = math.MaxUint32
				case "attempt":
					max = 100
				case "httpStatus":
					min = 100
					max = 599
				}
				if err != nil || n < min || n > max {
					return false
				}
			} else {
				s, ok := value.(string)
				if !ok || !hostingText(key, s) {
					return false
				}
			}
		}
	}
	if event {
		for _, key := range []string{"operationId", "operation", "kind", "timestamp"} {
			if value, ok := object[key].(string); !ok || value == "" {
				return false
			}
		}
	} else {
		for _, key := range []string{"events", "exportedAt", "historyPersistence"} {
			if _, ok := object[key]; !ok {
				return false
			}
		}
	}
	return true
}

func hostingText(key, s string) bool {
	if len(s) > 160 || !cleanText(s, 160, false) {
		return false
	}
	if s == "" {
		return true
	}
	switch key {
	case "timestamp", "exportedAt":
		return utcTime(s)
	case "operationId", "parentOperationId":
		return hostingUUID.MatchString(s)
	case "applicationVersion", "helperVersion", "qtVersion":
		return hostingVersion.MatchString(s)
	case "runtimeId":
		return runtimePattern.MatchString(s)
	case "operatingSystemVersion", "kernelVersion":
		return numericVersion.MatchString(s)
	case "operation":
		return oneOf(s, "check", "prepare", "import", "import_check", "cleanup", "host")
	case "kind":
		return oneOf(s, "started", "state", "diagnostic", "finished")
	case "outcome":
		return oneOf(s, "succeeded", "failed", "cancelled", "interrupted")
	case "source":
		return oneOf(s, "official", "mirror", "cache", "offline")
	case "component":
		return oneOf(s, "runtime", "forge", "java", "pack", "cache", "adapter", "helper", "client")
	case "transport":
		return oneOf(s, "off", "waiting", "connecting", "direct", "relay", "migrating", "reconnecting")
	case "historyPersistence":
		return oneOf(s, "available", "write_failed", "read_failed")
	case "architecture":
		return oneOf(s, "x86_64", "i386", "arm64", "arm")
	case "kernelType":
		return oneOf(s, "linux", "darwin", "winnt")
	case "expectedPackageId", "actualPackageId":
		return regexp.MustCompile(`^[0-9a-f]{20}$`).MatchString(s)
	case "expectedPlatform", "actualPlatform":
		return regexp.MustCompile(`^(linux|darwin|windows)-(amd64|arm64|386|arm)$`).MatchString(s)
	default:
		return token(s, 160)
	}
}
