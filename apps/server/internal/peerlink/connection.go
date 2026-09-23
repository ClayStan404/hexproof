// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package peerlink carries bounded application messages over an authenticated
// WebRTC data channel. Room authorization and relay fallback remain with the hub.
package peerlink

import (
	"context"
	"crypto/subtle"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"strings"
	"sync"
	"time"

	"github.com/pion/logging"
	"github.com/pion/webrtc/v4"
)

const (
	MaxMessageBytes = 4 << 20
	MaxSignalBytes  = 32 << 10
	chunkBytes      = 16 << 10
	chunkHeader     = 17
	maxBuffered     = 256 << 10
)

var ErrUnavailable = errors.New("direct peer transport unavailable")

// Grants travel only through an authenticated hub connection. The SDP DTLS
// fingerprint and an additional room binding/key handshake identify the peer.
type Config struct {
	BindingID string   `json:"bindingId"`
	Token     string   `json:"token"`
	Offerer   bool     `json:"offerer"`
	STUN      []string `json:"stun,omitempty"`
	// TURN is used by operator-hosted nodes. Player-hosted room grants retain
	// their discovery-only contract and do not supply relay credentials.
	TURN      []TURNServer `json:"turn,omitempty"`
	RelayOnly bool         `json:"relayOnly,omitempty"`
	// Loopback candidates are useful for isolated transport tests.
	IncludeLoopback bool `json:"-"`
}

type Signal struct {
	Description *webrtc.SessionDescription `json:"description,omitempty"`
	Candidate   *webrtc.ICECandidateInit   `json:"candidate,omitempty"`
}

// Callbacks must be nonblocking. They may enqueue into a bounded parent pipe,
// but must never put credentials, SDP or application messages into diagnostics.
type Callbacks struct {
	Signal  func(Signal)
	State   func(string)
	Message func([]byte)
}

type Connection struct {
	ctx              context.Context
	cancel           context.CancelFunc
	config           Config
	callbacks        Callbacks
	pc               *webrtc.PeerConnection
	mu               sync.Mutex
	sendMu           sync.Mutex
	channel          *webrtc.DataChannel
	authenticated    bool
	ready            bool
	closed           bool
	remoteCandidates []webrtc.ICECandidateInit
	candidateCount   int
	sent             uint64
	received         uint64
	assembling       uint64
	total            int
	assembly         []byte
	receiveTimer     *time.Timer
	connectTimer     *time.Timer
	bufferLow        chan struct{}
	closeOnce        sync.Once
}

func validID(value string) bool {
	if len(value) != 64 {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil
}

func New(parent context.Context, config Config, callbacks Callbacks) (*Connection, error) {
	return newConnection(parent, config, callbacks, nil)
}

func newConnection(parent context.Context, config Config, callbacks Callbacks, configure func(*webrtc.SettingEngine)) (*Connection, error) {
	if !validID(config.BindingID) || !validID(config.Token) || ValidateSTUNServers(config.STUN) != nil || ValidateTURNServers(config.TURN) != nil || (config.RelayOnly && len(config.TURN) == 0) {
		return nil, ErrUnavailable
	}
	settings := webrtc.SettingEngine{}
	settings.LoggerFactory = &logging.DefaultLoggerFactory{Writer: io.Discard, DefaultLogLevel: logging.LogLevelDisabled, ScopeLevels: map[string]logging.LogLevel{}}
	settings.SetIncludeLoopbackCandidate(config.IncludeLoopback)
	settings.SetICETimeouts(3*time.Second, 8*time.Second, time.Second)
	settings.SetNetworkTypes([]webrtc.NetworkType{webrtc.NetworkTypeUDP4, webrtc.NetworkTypeUDP6})
	settings.SetSCTPMaxMessageSize(chunkBytes + chunkHeader)
	settings.SetSCTPMaxReceiveBufferSize(1 << 20)
	if len(config.TURN) > 0 && !config.RelayOnly {
		// Give direct candidates a bounded head start; a relay remains available
		// when NAT traversal cannot complete. This is not a live path migration.
		settings.SetRelayAcceptanceMinWait(time.Second)
	}
	if configure != nil {
		configure(&settings)
	}
	api := webrtc.NewAPI(webrtc.WithSettingEngine(settings))
	rtcConfig := webrtc.Configuration{}
	if len(config.STUN) > 0 {
		rtcConfig.ICEServers = []webrtc.ICEServer{{URLs: config.STUN}}
	}
	for _, relay := range config.TURN {
		rtcConfig.ICEServers = append(rtcConfig.ICEServers, webrtc.ICEServer{
			URLs: relay.URLs, Username: relay.Username, Credential: relay.Credential,
		})
	}
	if config.RelayOnly {
		rtcConfig.ICETransportPolicy = webrtc.ICETransportPolicyRelay
	}
	pc, err := api.NewPeerConnection(rtcConfig)
	if err != nil {
		return nil, ErrUnavailable
	}
	ctx, cancel := context.WithCancel(parent)
	c := &Connection{ctx: ctx, cancel: cancel, config: config, callbacks: callbacks, pc: pc, bufferLow: make(chan struct{}, 1)}
	c.connectTimer = time.AfterFunc(12*time.Second, func() { c.fail() })
	pc.OnICECandidate(func(candidate *webrtc.ICECandidate) {
		if candidate != nil && callbacks.Signal != nil && ctx.Err() == nil {
			value := candidate.ToJSON()
			callbacks.Signal(Signal{Candidate: &value})
		}
	})
	pc.OnConnectionStateChange(func(state webrtc.PeerConnectionState) {
		switch state {
		case webrtc.PeerConnectionStateFailed, webrtc.PeerConnectionStateClosed:
			c.fail()
		case webrtc.PeerConnectionStateDisconnected:
			c.mu.Lock()
			c.ready = false
			c.mu.Unlock()
			c.state("relay")
		case webrtc.PeerConnectionStateConnected:
			c.mu.Lock()
			ready := c.authenticated && !c.closed
			c.ready = ready
			c.mu.Unlock()
			if ready {
				c.state("direct")
			}
		}
	})
	pc.OnDataChannel(func(channel *webrtc.DataChannel) {
		if config.Offerer {
			c.fail()
			return
		}
		c.attach(channel)
	})
	go func() { <-ctx.Done(); _ = c.Close() }()
	if config.Offerer {
		channel, err := pc.CreateDataChannel("hexproof-game", &webrtc.DataChannelInit{Protocol: ptr("hexproof.v1")})
		if err != nil {
			c.Close()
			return nil, ErrUnavailable
		}
		c.attach(channel)
	}
	return c, nil
}

func ptr[T any](value T) *T { return &value }

// Start emits the offer only after the caller has installed its event routing.
func (c *Connection) Start() error {
	if !c.config.Offerer {
		return nil
	}
	offer, err := c.pc.CreateOffer(nil)
	if err != nil {
		return ErrUnavailable
	}
	if err := c.pc.SetLocalDescription(offer); err != nil {
		return ErrUnavailable
	}
	if c.callbacks.Signal != nil {
		c.callbacks.Signal(Signal{Description: &offer})
	}
	return nil
}

func (c *Connection) ApplySignal(signal Signal) error {
	raw, err := json.Marshal(signal)
	if err != nil || len(raw) > MaxSignalBytes || (signal.Description == nil) == (signal.Candidate == nil) {
		return ErrUnavailable
	}
	if signal.Description != nil {
		description := *signal.Description
		if c.pc.RemoteDescription() != nil || strings.Count(description.SDP, "m=") != 1 ||
			!strings.Contains(description.SDP, "m=application ") ||
			(c.config.Offerer && description.Type != webrtc.SDPTypeAnswer) ||
			(!c.config.Offerer && description.Type != webrtc.SDPTypeOffer) {
			return ErrUnavailable
		}
		if c.pc.SetRemoteDescription(description) != nil {
			return ErrUnavailable
		}
		c.mu.Lock()
		candidates := c.remoteCandidates
		c.remoteCandidates = nil
		c.mu.Unlock()
		for _, candidate := range candidates {
			if c.pc.AddICECandidate(candidate) != nil {
				return ErrUnavailable
			}
		}
		if !c.config.Offerer {
			answer, err := c.pc.CreateAnswer(nil)
			if err != nil || c.pc.SetLocalDescription(answer) != nil {
				return ErrUnavailable
			}
			if c.callbacks.Signal != nil {
				c.callbacks.Signal(Signal{Description: &answer})
			}
		}
		return nil
	}
	if len(signal.Candidate.Candidate) > 2048 {
		return ErrUnavailable
	}
	c.mu.Lock()
	c.candidateCount++
	if c.closed || c.candidateCount > 64 {
		c.mu.Unlock()
		return ErrUnavailable
	}
	if c.pc.RemoteDescription() == nil {
		c.remoteCandidates = append(c.remoteCandidates, *signal.Candidate)
		c.mu.Unlock()
		return nil
	}
	c.mu.Unlock()
	if c.pc.AddICECandidate(*signal.Candidate) != nil {
		return ErrUnavailable
	}
	return nil
}

func (c *Connection) attach(channel *webrtc.DataChannel) {
	c.mu.Lock()
	if c.closed || c.channel != nil || channel.Label() != "hexproof-game" || channel.Protocol() != "hexproof.v1" || !channel.Ordered() || channel.MaxRetransmits() != nil || channel.MaxPacketLifeTime() != nil {
		c.mu.Unlock()
		c.fail()
		return
	}
	c.channel = channel
	c.mu.Unlock()
	channel.SetBufferedAmountLowThreshold(maxBuffered / 2)
	channel.OnBufferedAmountLow(func() {
		select {
		case c.bufferLow <- struct{}{}:
		default:
		}
	})
	channel.OnError(func(error) { c.fail() })
	channel.OnClose(func() { c.fail() })
	channel.OnOpen(func() {
		hello := append([]byte{0}, []byte(c.config.BindingID+c.config.Token)...)
		if channel.Send(hello) != nil {
			c.fail()
		}
	})
	channel.OnMessage(func(message webrtc.DataChannelMessage) {
		if message.IsString || !c.receive(message.Data) {
			c.fail()
		}
	})
}

func (c *Connection) Ready() bool { c.mu.Lock(); defer c.mu.Unlock(); return c.ready && !c.closed }

// Transport describes the selected route without exposing candidate addresses.
// The State callback keeps its legacy "direct" = authenticated/ready meaning;
// callers supporting TURN use this method to distinguish a relayed RTC route.
func (c *Connection) Transport() string {
	if !c.Ready() || c.pc == nil || c.pc.SCTP() == nil {
		return "connecting"
	}
	pair, err := c.pc.SCTP().Transport().ICETransport().GetSelectedCandidatePair()
	if err != nil || pair == nil {
		return "connecting"
	}
	if pair.Local.Typ == webrtc.ICECandidateTypeRelay || pair.Remote.Typ == webrtc.ICECandidateTypeRelay {
		return "relay"
	}
	return "direct"
}

func (c *Connection) state(state string) {
	if c.callbacks.State != nil {
		c.callbacks.State(state)
	}
}
func (c *Connection) fail() { c.cancel() }

func (c *Connection) Close() error {
	c.closeOnce.Do(func() {
		c.cancel()
		c.mu.Lock()
		c.closed, c.ready = true, false
		c.assembly, c.remoteCandidates = nil, nil
		if c.receiveTimer != nil {
			c.receiveTimer.Stop()
		}
		if c.connectTimer != nil {
			c.connectTimer.Stop()
		}
		c.mu.Unlock()
		_ = c.pc.Close()
		c.state("relay")
	})
	return nil
}

func (c *Connection) Send(ctx context.Context, message []byte) error {
	if len(message) == 0 || len(message) > MaxMessageBytes {
		return ErrUnavailable
	}
	c.sendMu.Lock()
	defer c.sendMu.Unlock()
	c.mu.Lock()
	if !c.ready || c.closed {
		c.mu.Unlock()
		return ErrUnavailable
	}
	channel := c.channel
	c.sent++
	id := c.sent
	c.mu.Unlock()
	for offset := 0; offset < len(message); {
		for channel.BufferedAmount() > maxBuffered {
			select {
			case <-ctx.Done():
				c.fail()
				return ctx.Err()
			case <-c.ctx.Done():
				return ErrUnavailable
			case <-c.bufferLow:
			}
		}
		end := min(offset+chunkBytes, len(message))
		frame := make([]byte, chunkHeader+end-offset)
		frame[0] = 1
		binary.BigEndian.PutUint64(frame[1:9], id)
		binary.BigEndian.PutUint32(frame[9:13], uint32(len(message)))
		binary.BigEndian.PutUint32(frame[13:17], uint32(offset))
		copy(frame[chunkHeader:], message[offset:end])
		if ctx.Err() != nil || channel.Send(frame) != nil {
			c.fail()
			return ErrUnavailable
		}
		offset = end
	}
	return nil
}

func (c *Connection) receive(frame []byte) bool {
	c.mu.Lock()
	if c.closed || len(frame) == 0 || len(frame) > chunkBytes+chunkHeader {
		c.mu.Unlock()
		return false
	}
	if frame[0] == 0 {
		valid := !c.authenticated && len(frame) == 129 && subtle.ConstantTimeCompare(frame[1:], []byte(c.config.BindingID+c.config.Token)) == 1
		if valid {
			c.authenticated, c.ready = true, true
			c.connectTimer.Stop()
		}
		c.mu.Unlock()
		if valid {
			c.state("direct")
		}
		return valid
	}
	if !c.authenticated || frame[0] != 1 || len(frame) <= chunkHeader {
		c.mu.Unlock()
		return false
	}
	id := binary.BigEndian.Uint64(frame[1:9])
	total, offset := int(binary.BigEndian.Uint32(frame[9:13])), int(binary.BigEndian.Uint32(frame[13:17]))
	if total < 1 || total > MaxMessageBytes || offset+len(frame)-chunkHeader > total || id <= c.received {
		c.mu.Unlock()
		return false
	}
	if c.assembly == nil {
		if offset != 0 {
			c.mu.Unlock()
			return false
		}
		c.assembling, c.total = id, total
		c.assembly = make([]byte, 0, total)
		c.receiveTimer = time.AfterFunc(10*time.Second, func() {
			c.mu.Lock()
			incomplete := c.assembling == id && c.assembly != nil
			c.mu.Unlock()
			if incomplete {
				c.fail()
			}
		})
	}
	if id != c.assembling || total != c.total || offset != len(c.assembly) {
		c.mu.Unlock()
		return false
	}
	c.assembly = append(c.assembly, frame[chunkHeader:]...)
	if len(c.assembly) != total {
		c.mu.Unlock()
		return true
	}
	message := c.assembly
	c.assembly, c.received = nil, id
	c.receiveTimer.Stop()
	c.mu.Unlock()
	if c.callbacks.Message != nil {
		c.callbacks.Message(message)
	}
	return true
}
