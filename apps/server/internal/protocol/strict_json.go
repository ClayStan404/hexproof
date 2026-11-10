// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package protocol

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"reflect"
	"strings"
)

// CheckUniqueJSONKeys rejects ambiguous recipes before any decoder can discard
// an earlier value. Duplicate keys are invalid even when their values agree.
func CheckUniqueJSONKeys(data []byte) error {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()
	var value func(int) error
	value = func(depth int) error {
		if depth > 128 {
			return fmt.Errorf("JSON nesting is too deep")
		}
		token, err := decoder.Token()
		if err != nil {
			return err
		}
		delim, ok := token.(json.Delim)
		if !ok {
			return nil
		}
		switch delim {
		case '{':
			keys := make(map[string]bool)
			for decoder.More() {
				key, err := decoder.Token()
				if err != nil {
					return err
				}
				name, ok := key.(string)
				if !ok || keys[name] {
					return fmt.Errorf("duplicate or invalid JSON key")
				}
				keys[name] = true
				if err := value(depth + 1); err != nil {
					return err
				}
			}
		case '[':
			for decoder.More() {
				if err := value(depth + 1); err != nil {
					return err
				}
			}
		default:
			return fmt.Errorf("unexpected JSON delimiter")
		}
		_, err = decoder.Token()
		return err
	}
	if err := value(0); err != nil {
		return err
	}
	if _, err := decoder.Token(); err != io.EOF {
		return fmt.Errorf("expected one JSON value")
	}
	return nil
}

func decodeStrict(data []byte, dst any) error {
	if err := CheckUniqueJSONKeys(data); err != nil {
		return err
	}
	// encoding/json accepts case-insensitive aliases even with
	// DisallowUnknownFields. Require the exact schema names so two differently
	// cased keys cannot overwrite one field in a locked recipe.
	if err := checkFieldNames(data, reflect.TypeOf(dst).Elem()); err != nil {
		return err
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	return decoder.Decode(dst)
}

func checkFieldNames(data []byte, typ reflect.Type) error {
	for typ.Kind() == reflect.Pointer {
		typ = typ.Elem()
	}
	if bytes.Equal(bytes.TrimSpace(data), []byte("null")) {
		return nil
	}
	switch typ.Kind() {
	case reflect.Struct:
		fields := make(map[string]reflect.Type, typ.NumField())
		for i := 0; i < typ.NumField(); i++ {
			field := typ.Field(i)
			name := strings.Split(field.Tag.Get("json"), ",")[0]
			if name != "" && name != "-" {
				fields[name] = field.Type
			}
		}
		var object map[string]json.RawMessage
		if err := json.Unmarshal(data, &object); err != nil {
			return err
		}
		for name, value := range object {
			field, ok := fields[name]
			if !ok {
				return fmt.Errorf("unknown JSON field %q", name)
			}
			if err := checkFieldNames(value, field); err != nil {
				return err
			}
		}
	case reflect.Slice:
		var values []json.RawMessage
		if err := json.Unmarshal(data, &values); err != nil {
			return err
		}
		for _, value := range values {
			if err := checkFieldNames(value, typ.Elem()); err != nil {
				return err
			}
		}
	}
	return nil
}

func (c *TournamentCreate) UnmarshalJSON(data []byte) error {
	// Bound the original encoded plan before building any recipe slices. Whitespace
	// counts too; internal normalization must not hide an oversized input.
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		return err
	}
	if fields == nil {
		return fmt.Errorf("tournament creation must be an object")
	}
	if _, product := fields["product"]; product {
		if _, plan := fields["plan"]; plan {
			return fmt.Errorf("supply product or plan, never both")
		}
	}
	if raw, ok := fields["plan"]; ok && len(raw) > 800*1024 {
		return fmt.Errorf("combined products too large: pack plan must fit 800 KiB; select fewer or smaller products")
	}
	type plain TournamentCreate
	var decoded plain
	if err := decodeStrict(data, &decoded); err != nil {
		return err
	}
	*c = TournamentCreate(decoded)
	return nil
}

func (c *TournamentStart) UnmarshalJSON(data []byte) error {
	type plain TournamentStart
	var decoded plain
	if err := decodeStrict(data, &decoded); err != nil {
		return err
	}
	*c = TournamentStart(decoded)
	return nil
}
