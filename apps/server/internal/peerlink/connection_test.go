// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package peerlink

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/binary"
	"github.com/pion/webrtc/v4"
	"strings"
	"sync"
	"testing"
	"time"
)

type routedSignal struct {
	to     int
	signal Signal
}

func testPair(t *testing.T, wrongBinding bool) ([2]*Connection, [2]chan []byte) {
	t.Helper()
	return testConfiguredPair(t, wrongBinding, nil)
}

func testConfiguredPair(t *testing.T, wrongBinding bool, configure func(int, *webrtc.SettingEngine)) ([2]*Connection, [2]chan []byte) {
	t.Helper()
	ctx, cancel := context.WithCancel(t.Context())
	signals := make(chan routedSignal, 128)
	errors := make(chan error, 128)
	messages := [2]chan []byte{make(chan []byte, 8), make(chan []byte, 8)}
	var peers [2]*Connection
	for i := range 2 {
		config := Config{BindingID: strings.Repeat("a", 64), Token: strings.Repeat("b", 64), Offerer: i == 0, IncludeLoopback: true}
		if wrongBinding && i == 1 {
			config.BindingID = strings.Repeat("c", 64)
		}
		peer, err := newConnection(ctx, config, Callbacks{
			Signal: func(signal Signal) {
				select {
				case signals <- routedSignal{1 - i, signal}:
				default:
					errors <- ErrUnavailable
				}
			},
			Message: func(message []byte) {
				select {
				case messages[i] <- message:
				default:
					errors <- ErrUnavailable
				}
			},
		}, func(settings *webrtc.SettingEngine) {
			if configure != nil {
				configure(i, settings)
			}
		})
		if err != nil {
			cancel()
			t.Fatal(err)
		}
		peers[i] = peer
	}
	finished := make(chan struct{})
	go func() {
		defer close(finished)
		for {
			select {
			case <-ctx.Done():
				return
			case signal := <-signals:
				if err := peers[signal.to].ApplySignal(signal.signal); err != nil {
					select {
					case errors <- err:
					default:
					}
				}
			}
		}
	}()
	t.Cleanup(func() {
		cancel()
		for _, peer := range peers {
			_ = peer.Close()
		}
		select {
		case <-finished:
		case <-time.After(2 * time.Second):
			t.Error("signaling goroutine leaked")
		}
	})
	if peers[0].Start() != nil {
		t.Fatal("could not offer")
	}
	if wrongBinding {
		return peers, messages
	}
	timeout := time.After(5 * time.Second)
	for !peers[0].Ready() || !peers[1].Ready() {
		select {
		case err := <-errors:
			t.Fatal(err)
		case <-timeout:
			t.Fatal("loopback ICE/DTLS authentication did not complete")
		case <-time.After(5 * time.Millisecond):
		}
	}
	return peers, messages
}

func TestRealDataChannelReassemblesBothDirectionsAndCloses(t *testing.T) {
	peers, messages := testPair(t, false)
	for sender := range 2 {
		payload := make([]byte, 750000)
		if _, err := rand.Read(payload); err != nil {
			t.Fatal(err)
		}
		ctx, cancel := context.WithTimeout(t.Context(), 3*time.Second)
		if err := peers[sender].Send(ctx, payload); err != nil {
			cancel()
			t.Fatal(err)
		}
		select {
		case got := <-messages[1-sender]:
			if !bytes.Equal(got, payload) {
				t.Fatal("fragmented payload changed")
			}
		case <-ctx.Done():
			t.Fatal("direct delivery timed out")
		}
		cancel()
	}
	_ = peers[0].Close()
	deadline := time.After(3 * time.Second)
	for peers[1].Ready() {
		select {
		case <-deadline:
			t.Fatal("remote close did not switch away from direct")
		case <-time.After(time.Millisecond):
		}
	}
	if err := peers[0].Send(t.Context(), []byte("late")); err == nil {
		t.Fatal("closed channel accepted a game action")
	}
}

func TestCrossRoomHandshakeNeverAcceptsApplicationData(t *testing.T) {
	peers, messages := testPair(t, true)
	deadline := time.After(5 * time.Second)
	for {
		if peers[0].Ready() || peers[1].Ready() {
			t.Fatal("wrong room binding authenticated")
		}
		select {
		case <-peers[0].ctx.Done():
			if len(messages[0]) != 0 || len(messages[1]) != 0 {
				t.Fatal("cross-room payload delivered")
			}
			return
		case <-deadline:
			t.Fatal("bad binding did not close")
		case <-time.After(time.Millisecond):
		}
	}
}

func TestFragmentBoundsOrderAndDuplicateIDs(t *testing.T) {
	makeFrame := func(id uint64, total, offset int, data string) []byte {
		frame := make([]byte, chunkHeader+len(data))
		frame[0] = 1
		binary.BigEndian.PutUint64(frame[1:9], id)
		binary.BigEndian.PutUint32(frame[9:13], uint32(total))
		binary.BigEndian.PutUint32(frame[13:17], uint32(offset))
		copy(frame[chunkHeader:], data)
		return frame
	}
	ctx, cancel := context.WithCancel(t.Context())
	defer cancel()
	c := &Connection{authenticated: true, ctx: ctx, cancel: cancel}
	for _, frame := range [][]byte{makeFrame(1, MaxMessageBytes+1, 0, "a"), makeFrame(1, 3, 1, "b"), makeFrame(0, 1, 0, "a"), {1}} {
		if c.receive(frame) {
			t.Fatal("invalid fragment was accepted")
		}
	}
	if !c.receive(makeFrame(1, 4, 0, "ab")) {
		t.Fatal("valid first fragment rejected")
	}
	defer c.receiveTimer.Stop()
	if c.receive(makeFrame(1, 4, 1, "bc")) || c.receive(makeFrame(2, 4, 2, "cd")) {
		t.Fatal("overlap or interleaved message accepted")
	}
	if !c.receive(makeFrame(1, 4, 2, "cd")) {
		t.Fatal("valid last fragment rejected")
	}
	if c.receive(makeFrame(1, 1, 0, "x")) {
		t.Fatal("duplicate completed message was replayed")
	}
}

func TestConcurrentSendAndCancellationDoNotLeak(t *testing.T) {
	peers, _ := testPair(t, false)
	ctx, cancel := context.WithCancel(t.Context())
	var group sync.WaitGroup
	for range 4 {
		group.Go(func() { _ = peers[0].Send(ctx, make([]byte, 250000)) })
	}
	cancel()
	_ = peers[0].Close()
	finished := make(chan struct{})
	go func() { group.Wait(); close(finished) }()
	select {
	case <-finished:
	case <-time.After(2 * time.Second):
		t.Fatal("cancelled send leaked")
	}
}
