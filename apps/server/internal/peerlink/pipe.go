// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package peerlink

import (
	"bufio"
	"context"
	"encoding/json"
	"io"
	"sync/atomic"
	"time"
)

// RunPipe runs the transport-only helper. No Java, runtime cache, shell, local
// server or inbound TCP listener is involved. EOF is the parent's lifetime lease.
func RunPipe(parent context.Context, input io.Reader, output io.Writer) error {
	ctx, cancel := context.WithCancel(parent)
	defer cancel()
	scanner := bufio.NewScanner(input)
	scanner.Buffer(make([]byte, 8192), MaxMessageBytes+(64<<10))
	if !scanner.Scan() || len(scanner.Bytes()) > 8192 {
		return ErrUnavailable
	}
	var config Config
	if json.Unmarshal(scanner.Bytes(), &config) != nil {
		return ErrUnavailable
	}
	events := make(chan []byte, 64)
	var queued atomic.Int64
	emit := func(value map[string]any) {
		value["bindingId"] = config.BindingID
		raw, err := json.Marshal(value)
		if err != nil || queued.Add(int64(len(raw))) > 8<<20 {
			cancel()
			return
		}
		select {
		case events <- raw:
		default:
			queued.Add(-int64(len(raw)))
			cancel()
		}
	}
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case raw := <-events:
				_, err := output.Write(append(raw, '\n'))
				queued.Add(-int64(len(raw)))
				if err != nil {
					cancel()
					return
				}
			}
		}
	}()
	connection, err := New(ctx, config, Callbacks{
		Signal: func(s Signal) { emit(map[string]any{"signal": s}) },
		State:  func(s string) { emit(map[string]any{"state": s}) },
		Message: func(raw []byte) {
			if !json.Valid(raw) {
				cancel()
				return
			}
			emit(map[string]any{"message": json.RawMessage(raw)})
		},
	})
	if err != nil {
		return err
	}
	defer connection.Close()
	commands := make(chan []byte, 1)
	go func() {
		defer cancel()
		for scanner.Scan() {
			data := append([]byte(nil), scanner.Bytes()...)
			select {
			case commands <- data:
			case <-ctx.Done():
				return
			}
		}
	}()
	if err := connection.Start(); err != nil {
		return err
	}
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case raw := <-commands:
			var command struct {
				Signal  *Signal         `json:"signal"`
				Message json.RawMessage `json:"message"`
			}
			if json.Unmarshal(raw, &command) != nil || (command.Signal == nil) == (len(command.Message) == 0) {
				return ErrUnavailable
			}
			if command.Signal != nil {
				if connection.ApplySignal(*command.Signal) != nil {
					return ErrUnavailable
				}
			} else {
				sendCtx, stop := context.WithTimeout(ctx, 3*time.Second)
				err := connection.Send(sendCtx, command.Message)
				stop()
				if err != nil {
					return err
				}
			}
		}
	}
}
