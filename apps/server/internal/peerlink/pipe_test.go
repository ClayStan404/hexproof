// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package peerlink

import (
	"context"
	"encoding/json"
	"io"
	"strings"
	"testing"
	"time"
)

func TestPipeParentDeathAndInvalidConfiguration(t *testing.T) {
	for _, text := range []string{"", "{}\n", strings.Repeat("x", 9000) + "\n"} {
		if RunPipe(t.Context(), strings.NewReader(text), io.Discard) == nil {
			t.Fatal("invalid pipe configuration was accepted")
		}
	}
	input, parent := io.Pipe()
	ctx, cancel := context.WithCancel(t.Context())
	defer cancel()
	defer input.Close()
	defer parent.Close()
	finished := make(chan error, 1)
	go func() { finished <- RunPipe(ctx, input, io.Discard) }()
	raw, _ := json.Marshal(Config{BindingID: strings.Repeat("a", 64), Token: strings.Repeat("b", 64), Offerer: true})
	if _, err := parent.Write(append(raw, '\n')); err != nil {
		t.Fatal(err)
	}
	_ = parent.Close()
	select {
	case <-finished:
	case <-time.After(2 * time.Second):
		t.Fatal("transport helper survived parent EOF")
	}
}
