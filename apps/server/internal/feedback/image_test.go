// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"hash/crc32"
	"image"
	"image/png"
	"testing"
	"time"
)

func parsePublicImage(t *testing.T, raw []byte, ctx context.Context, decodes chan struct{}) (PublicSubmission, error) {
	t.Helper()
	c, sub := publicFixture(t)
	a := Attachment{ID: "screenshot-1", Kind: "screenshot", MediaType: "image/png", ByteLength: int64(len(raw)), SHA256: hashBytes(raw)}
	sub.Manifest.Attachments = []Attachment{a}
	manifest, err := json.Marshal(sub.Manifest)
	if err != nil {
		t.Fatal(err)
	}
	body, kind := multipartBody(t, manifest, []Blob{{Attachment: a, Bytes: raw}})
	return parsePublicSubmission(ctx, bytes.NewReader(body), kind, sub.Manifest.SubmissionID, PublicDigest(manifest),
		time.Date(2026, 10, 22, 12, 1, 0, 0, time.UTC), c, decodes)
}

func pngChunk(kind string, payload []byte) []byte {
	chunk := make([]byte, len(payload)+12)
	binary.BigEndian.PutUint32(chunk, uint32(len(payload)))
	copy(chunk[4:8], kind)
	copy(chunk[8:], payload)
	binary.BigEndian.PutUint32(chunk[len(chunk)-4:], crc32.ChecksumIEEE(chunk[4:len(chunk)-4]))
	return chunk
}

func TestPublicImagePreservesApprovedEncoding(t *testing.T) {
	_, sub := publicFixture(t)
	raw := addPublicImage(t, sub).Blobs[0].Bytes
	// Physical resolution is allowed in public PNGs but is stripped by V1's
	// normalization. V2 must preserve the reviewed encoding, length and digest.
	resolution := make([]byte, 9)
	binary.BigEndian.PutUint32(resolution, 3780)
	binary.BigEndian.PutUint32(resolution[4:], 3780)
	resolution[8] = 1
	approved := append(append(append([]byte{}, raw[:33]...), pngChunk("pHYs", resolution)...), raw[33:]...)
	normalized, err := normalizeImage(approved, "image/png")
	if err != nil || bytes.Equal(normalized, approved) {
		t.Fatalf("fixture must have a distinct valid normalized encoding: %v", err)
	}
	parsed, err := parsePublicImage(t, approved, context.Background(), make(chan struct{}, 1))
	if err != nil || len(parsed.Blobs) != 1 {
		t.Fatalf("public acceptance: %v", err)
	}
	got := parsed.Blobs[0]
	if !bytes.Equal(got.Bytes, approved) || got.Attachment.ByteLength != int64(len(approved)) || got.Attachment.SHA256 != hashBytes(approved) {
		t.Fatal("public image changed after preview")
	}
}

func TestPublicImageRequiresCompleteBoundedDecode(t *testing.T) {
	_, sub := publicFixture(t)
	raw := addPublicImage(t, sub).Blobs[0].Bytes
	corrupt := append([]byte{}, raw...)
	for p := 8; p+12 <= len(corrupt); {
		n := int(binary.BigEndian.Uint32(corrupt[p : p+4]))
		if string(corrupt[p+4:p+8]) == "IDAT" {
			// Preserve chunk framing and CRC, but break the compressed pixel data.
			corrupt[p+8] = 0
			binary.BigEndian.PutUint32(corrupt[p+8+n:], crc32.ChecksumIEEE(corrupt[p+4:p+8+n]))
			break
		}
		p += n + 12
	}
	if _, _, err := image.DecodeConfig(bytes.NewReader(corrupt)); err != nil || !publicImage(corrupt, "image/png") {
		t.Fatal("fixture must pass header and public chunk validation")
	}
	withSize := func(width, height uint32) []byte {
		modified := append([]byte{}, raw...)
		binary.BigEndian.PutUint32(modified[16:], width)
		binary.BigEndian.PutUint32(modified[20:], height)
		binary.BigEndian.PutUint32(modified[29:], crc32.ChecksumIEEE(modified[12:29]))
		return modified
	}
	for name, invalid := range map[string][]byte{
		"corrupt pixels": corrupt,
		"edge limit":     withSize(8193, 1),
		"pixel limit":    withSize(8192, 2000),
		"trailing bytes": append(append([]byte{}, raw...), 0),
		"metadata":       append(append(append([]byte{}, raw[:33]...), pngChunk("tEXt", []byte("private\x00data"))...), raw[33:]...),
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := parsePublicImage(t, invalid, context.Background(), make(chan struct{}, 1)); !errors.Is(err, ErrInvalid) {
				t.Fatalf("invalid image accepted: %v", err)
			}
		})
	}
}

func TestPublicImageDecodeWaitHonorsCancellation(t *testing.T) {
	_, sub := publicFixture(t)
	raw := addPublicImage(t, sub).Blobs[0].Bytes
	decodes := make(chan struct{}, 1)
	decodes <- struct{}{}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := parsePublicImage(t, raw, ctx, decodes); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("saturated decode ignored cancellation: %v", err)
	}
	if len(decodes) != 1 {
		t.Fatal("cancelled request released another request's decode slot")
	}
}

func BenchmarkImageValidation(b *testing.B) {
	im := image.NewNRGBA(image.Rect(0, 0, 1280, 720))
	for y := 0; y < 720; y++ {
		for x := 0; x < 1280; x++ {
			i := y*im.Stride + x*4
			im.Pix[i], im.Pix[i+1], im.Pix[i+2], im.Pix[i+3] = byte(x*17+y*3), byte(x+y*7), byte(x*5+y*11), 255
		}
	}
	var encoded bytes.Buffer
	if err := png.Encode(&encoded, im); err != nil {
		b.Fatal(err)
	}
	raw := encoded.Bytes()
	for _, name := range []string{"public_decode", "legacy_normalize"} {
		b.Run(name, func(b *testing.B) {
			b.ReportAllocs()
			b.SetBytes(int64(len(raw)))
			for b.Loop() {
				var err error
				if name == "public_decode" {
					_, err = decodeImage(raw, "image/png")
				} else {
					_, err = normalizeImage(raw, "image/png")
				}
				if err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}
