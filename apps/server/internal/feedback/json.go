// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"unicode/utf8"
)

func readBounded(r io.Reader, maximum int64) ([]byte, error) {
	b, err := io.ReadAll(io.LimitReader(r, maximum+1))
	if err != nil {
		return nil, err
	}
	if int64(len(b)) > maximum {
		return nil, fmt.Errorf("size limit")
	}
	return b, nil
}

// encoding/json alone accepts repeated keys. Validate the token stream before
// decoding into closed DTOs, including nested objects and bounded nesting.
func decodeClosed(raw []byte, target any) error {
	if !utf8.Valid(raw) {
		return ErrInvalid
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	d.UseNumber()
	if err := walkJSON(d, 0); err != nil {
		return err
	}
	if _, err := d.Token(); err != io.EOF {
		return ErrInvalid
	}
	d = json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	return d.Decode(target)
}

func walkJSON(d *json.Decoder, depth int) error {
	if depth > 16 {
		return ErrInvalid
	}
	t, err := d.Token()
	if err != nil {
		return ErrInvalid
	}
	if s, ok := t.(string); ok && len(s) > 8192 {
		return ErrInvalid
	}
	delim, ok := t.(json.Delim)
	if !ok {
		return nil
	}
	switch delim {
	case '{':
		keys := map[string]bool{}
		for d.More() {
			t, err := d.Token()
			if err != nil {
				return ErrInvalid
			}
			k, ok := t.(string)
			if !ok || len(k) > 128 || keys[k] || len(keys) >= 256 {
				return ErrInvalid
			}
			keys[k] = true
			if err := walkJSON(d, depth+1); err != nil {
				return err
			}
		}
	case '[':
		for n := 0; d.More(); n++ {
			if n >= 1024 {
				return ErrInvalid
			}
			if err := walkJSON(d, depth+1); err != nil {
				return err
			}
		}
	default:
		return ErrInvalid
	}
	end, err := d.Token()
	if err != nil || (delim == '{' && end != json.Delim('}')) || (delim == '[' && end != json.Delim(']')) {
		return ErrInvalid
	}
	return nil
}
