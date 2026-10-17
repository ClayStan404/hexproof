// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/textproto"
	"os"
	"strings"
	"sync"
	"testing"
)

func multipartBody(t *testing.T, manifest []byte, blobs []Blob) ([]byte, string) {
	t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	w, err := mw.CreatePart(textproto.MIMEHeader{"Content-Disposition": {`form-data; name="manifest"`}, "Content-Type": {"application/json"}})
	if err != nil {
		t.Fatal(err)
	}
	w.Write(manifest)
	for _, b := range blobs {
		w, err = mw.CreatePart(textproto.MIMEHeader{"Content-Disposition": {`form-data; name="` + b.Attachment.ID + `"`}, "Content-Type": {b.Attachment.MediaType}})
		if err != nil {
			t.Fatal(err)
		}
		w.Write(b.Bytes)
	}
	if err := mw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes(), mw.FormDataContentType()
}

func rawManifest(t *testing.T) []byte {
	t.Helper()
	raw, err := os.ReadFile("../../../../testdata/feedback/v1/valid-no-attachments.json")
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func request(h http.Handler, method string, body []byte, kind, digest string, secret []byte) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, "http://localhost/feedback/v1/submissions/"+testID, bytes.NewReader(body))
	r.Header.Set("Authorization", "Feedback "+base64.RawURLEncoding.EncodeToString(secret))
	if method == "PUT" {
		r.Header.Set("Content-Type", kind)
		r.Header.Set("X-Feedback-Digest", digest)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func TestHTTPSharedFixtureResponseLossAndDuplicateConcurrentPUT(t *testing.T) {
	s, _ := testStore(t)
	limits := Limits{PerSourceSubmissions: 100, GlobalSubmissions: 1000}
	h := NewHandler(s, limits, nil)
	raw := rawManifest(t)
	body, kind := multipartBody(t, raw, nil)
	var wg sync.WaitGroup
	codes := make(chan int, 8)
	for range 8 {
		wg.Add(1)
		go func() { defer wg.Done(); codes <- request(h, "PUT", body, kind, Digest(raw), testSecret).Code }()
	}
	wg.Wait()
	close(codes)
	created := 0
	for code := range codes {
		if code == 201 {
			created++
		}
		if code != 201 && code != 200 && code != 503 {
			t.Fatalf("unexpected response %d", code)
		}
	}
	if created != 1 {
		t.Fatalf("created %d times", created)
	}
	got := request(h, "GET", nil, "", "", testSecret)
	if got.Code != 200 {
		t.Fatal(got.Code, got.Body.String())
	}
	var receipt Receipt
	if json.Unmarshal(got.Body.Bytes(), &receipt) != nil || receipt.Receipt != testID || receipt.State != "received" {
		t.Fatal(got.Body.String())
	}
	if got.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("cacheable capability response")
	}
	if got := request(h, "PUT", nil, kind, Digest(raw), testSecret); got.Code != 200 {
		t.Fatal("authenticated bodyless retry", got.Code)
	}
	if got := request(h, "PUT", nil, kind, hashBytes([]byte("different")), testSecret); got.Code != 409 {
		t.Fatal(got.Code)
	}
	if got := request(h, "GET", nil, "", "", bytes.Repeat([]byte{1}, 32)); got.Code != 404 {
		t.Fatal(got.Code)
	}
	if job, err := s.Claim(context.Background()); err != nil || job == nil {
		t.Fatal(job, err)
	}
	if job, err := s.Claim(context.Background()); err != nil || job != nil {
		t.Fatal("duplicate mail", job, err)
	}
}

func TestHTTPRejectsMalformedAndOverlongUploads(t *testing.T) {
	for _, test := range []struct {
		name     string
		manifest []byte
		digest   string
	}{
		{"duplicate key", bytes.Replace(rawManifest(t), []byte(`"schemaVersion": 1`), []byte(`"schemaVersion": 1, "schemaVersion": 1`), 1), ""},
		{"unknown field", bytes.Replace(rawManifest(t), []byte(`"category":`), []byte(`"privateToken":"secret", "category":`), 1), ""},
		{"incorrect hash", rawManifest(t), strings.Repeat("a", 64)},
		{"stale freeze", bytes.Replace(rawManifest(t), []byte("2026-10-09"), []byte("2026-09-01"), 1), ""},
	} {
		t.Run(test.name, func(t *testing.T) {
			s, _ := testStore(t)
			h := NewHandler(s, Limits{}, nil)
			body, kind := multipartBody(t, test.manifest, nil)
			digest := test.digest
			if digest == "" {
				digest = Digest(test.manifest)
			}
			w := request(h, "PUT", body, kind, digest, testSecret)
			if w.Code != 422 {
				t.Fatal(w.Code, w.Body.String())
			}
			if len(s.IDs()) != 0 {
				t.Fatal("invalid upload committed")
			}
		})
	}
	t.Run("chunked MIME epilogue", func(t *testing.T) {
		s, _ := testStore(t)
		h := NewHandler(s, Limits{}, nil)
		raw := rawManifest(t)
		body, kind := multipartBody(t, raw, nil)
		body = append(body, bytes.Repeat([]byte{'x'}, MaxUpload)...)
		r := httptest.NewRequest("PUT", "http://localhost/feedback/v1/submissions/"+testID, io.NopCloser(bytes.NewReader(body)))
		r.ContentLength = -1
		r.Header.Set("Content-Type", kind)
		r.Header.Set("Authorization", "Feedback "+base64.RawURLEncoding.EncodeToString(testSecret))
		r.Header.Set("X-Feedback-Digest", Digest(raw))
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != 413 {
			t.Fatal(w.Code, w.Body.String())
		}
		if len(s.IDs()) != 0 {
			t.Fatal("oversized chunked request committed")
		}
	})
}

func TestImagesAndDiagnosticsUseClosedExports(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 3, 3))
	img.Set(1, 1, color.RGBA{R: 200, A: 255})
	var pngBytes bytes.Buffer
	if err := png.Encode(&pngBytes, img); err != nil {
		t.Fatal(err)
	}
	normalized, err := normalizeImage(pngBytes.Bytes(), "image/png")
	if err != nil || len(normalized) == 0 {
		t.Fatal(err)
	}
	if _, err := normalizeImage(pngBytes.Bytes(), "image/jpeg"); err == nil {
		t.Fatal("type confusion accepted")
	}
	animated := append([]byte{}, pngBytes.Bytes()[:8]...)
	animated = append(animated, []byte{0, 0, 0, 0, 'a', 'c', 'T', 'L', 0, 0, 0, 0}...)
	animated = append(animated, pngBytes.Bytes()[8:]...)
	if _, err := normalizeImage(animated, "image/png"); err == nil {
		t.Fatal("animation accepted")
	}
	raw, err := os.ReadFile("../../../../testdata/protocol/v1/error-forge-crash-edh.json")
	if err != nil {
		t.Fatal(err)
	}
	var wrapper struct {
		Payload struct {
			Report json.RawMessage `json:"rulesCrashReport"`
		} `json:"payload"`
	}
	if json.Unmarshal(raw, &wrapper) != nil {
		t.Fatal("fixture")
	}
	if normalized, err := normalizeCrash(wrapper.Payload.Report, Attachment{}); err != nil || len(normalized) == 0 {
		t.Fatal("existing crash export rejected", err)
	}
	private := bytes.Replace(wrapper.Payload.Report, []byte(`"schemaVersion": 1`), []byte(`"schemaVersion": 1,"rawStderr":"secret"`), 1)
	if _, err := normalizeCrash(private, Attachment{}); err == nil {
		t.Fatal("private crash field accepted")
	}
	host := []byte(`{"schemaVersion":2,"events":[],"exportedAt":"2026-10-09T12:00:00.000Z","historyPersistence":"available","operatingSystem":"linux","applicationVersion":"2.5.0","runtimeId":"","recentStates":[],"state":"ready","ready":true,"hosting":false}`)
	if _, err := normalizeHosting(host, Attachment{}); err != nil {
		t.Fatal("existing hosting export rejected", err)
	}
	if _, err := normalizeHosting(bytes.Replace(host, []byte(`"events":[]`), []byte(`"events":[],"serverUrl":"https://private"`), 1), Attachment{}); err == nil {
		t.Fatal("private hosting field accepted")
	}
	s, _ := testStore(t)
	h := NewHandler(s, Limits{}, nil)
	m := testSubmission(t).Manifest
	a := Attachment{ID: "image_1", Kind: "screenshot", MediaType: "image/png", ByteLength: int64(pngBytes.Len()), SHA256: hashBytes(pngBytes.Bytes())}
	m.Attachments = []Attachment{a}
	manifest, _ := json.Marshal(m)
	body, kind := multipartBody(t, manifest, []Blob{{a, pngBytes.Bytes()}})
	if w := request(h, "PUT", body, kind, Digest(manifest), testSecret); w.Code != 201 {
		t.Fatal(w.Code, w.Body.String())
	}
}

func TestProxyAndSourceBounds(t *testing.T) {
	s, _ := testStore(t)
	h := NewHandler(s, Limits{}, []string{"127.0.0.0/8"})
	r := httptest.NewRequest("GET", "http://localhost", nil)
	r.RemoteAddr = "192.0.2.5:1234"
	r.Header.Set("X-Forwarded-For", "198.51.100.1")
	if got := h.source(r); got != "192.0.2.5" {
		t.Fatal(got)
	}
	r.RemoteAddr = "127.0.0.1:1234"
	r.Header.Set("X-Forwarded-For", "198.51.100.1, 2001:db8::1234")
	if got := h.source(r); got != "2001:db8::/64" {
		t.Fatal(got)
	}
	for i := 0; i < 4096; i++ {
		h.limiter.sources[string(rune(i))] = &buckets{last: testNow, byKind: map[string]bucket{}}
	}
	if h.limiter.allow("new", "requests", 1, 5, 100, testNow) {
		t.Fatal("unbounded rate keys")
	}
}
