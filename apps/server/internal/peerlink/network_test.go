// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package peerlink

import (
	"bytes"
	"context"
	"io"
	"sync/atomic"
	"testing"
	"time"

	"github.com/pion/logging"
	"github.com/pion/transport/v4/vnet"
	"github.com/pion/webrtc/v4"
)

func TestDelayPacketLossAndUDPBlackhole(t *testing.T) {
	router, err := vnet.NewRouter(&vnet.RouterConfig{CIDR: "192.0.2.0/24", MinDelay: 30 * time.Millisecond, MaxJitter: 10 * time.Millisecond,
		LoggerFactory: &logging.DefaultLoggerFactory{Writer: io.Discard, DefaultLogLevel: logging.LogLevelDisabled, ScopeLevels: map[string]logging.LogLevel{}},
	})
	if err != nil {
		t.Fatal(err)
	}
	var packets atomic.Uint64
	var blackhole atomic.Bool
	router.AddChunkFilter(func(vnet.Chunk) bool { return !blackhole.Load() && packets.Add(1)%13 != 0 })
	var nets [2]*vnet.Net
	for i, ip := range []string{"192.0.2.10", "192.0.2.11"} {
		nets[i], err = vnet.NewNet(&vnet.NetConfig{StaticIPs: []string{ip}})
		if err != nil || router.AddNet(nets[i]) != nil {
			t.Fatal("virtual peer interface unavailable", err)
		}
	}
	if router.Start() != nil {
		t.Fatal("virtual network failed")
	}
	t.Cleanup(func() { _ = router.Stop() })
	peers, messages := testConfiguredPair(t, false, func(i int, settings *webrtc.SettingEngine) { settings.SetNet(nets[i]) })
	payload := bytes.Repeat([]byte("private viewer data"), 12000)
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	defer cancel()
	started := time.Now()
	if peers[0].Send(ctx, payload) != nil {
		t.Fatal("lossy send failed")
	}
	select {
	case got := <-messages[1]:
		if !bytes.Equal(got, payload) {
			t.Fatal("loss/retransmission changed message")
		}
	case <-ctx.Done():
		t.Fatal("lossy data channel failed to retransmit")
	}
	t.Logf("30ms + 0..10ms each way, every 13th UDP packet dropped: %d bytes in %s", len(payload), time.Since(started))
	blackhole.Store(true)
	short, stop := context.WithTimeout(t.Context(), 250*time.Millisecond)
	defer stop()
	if peers[0].Send(short, make([]byte, MaxMessageBytes)) == nil {
		t.Fatal("blackhole failed to bound queued delivery")
	}
	deadline := time.After(time.Second)
	for peers[0].Ready() {
		select {
		case <-deadline:
			t.Fatal("uncertain partial delivery did not fall back")
		case <-time.After(time.Millisecond):
		}
	}
	select {
	case <-messages[1]:
		t.Fatal("partial message escaped to game handler")
	default:
	}
}
