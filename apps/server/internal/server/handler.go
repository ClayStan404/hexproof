// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"net"
	"sync"
	"time"

	"hexproof/server/internal/protocol"
)

// Lock order for room mutations:
//  1. tournament opMu, when a tournament command also mutates a pairing room
//  2. room operation lock (opMu)
//  3. Hub.mu for registry lookup (released before reducing)
//  4. room state lock (entry.mu)
//
// Hub.mu may be taken again after opMu for membership snapshots (membersOf).
// Grant mutexes (zoneDumpMu, publicZoneMoveMu) may be held with opMu during
// consent flows. resumeMu is a leaf: it may be taken while opMu is held (see
// restoreResumeHold and removeRoom), but no room lock may be acquired while it
// is held, so expireResumeHold releases it before calling lockRoomOperation and
// must itself be called only after any room opMu is released.
//
// Pairing-room deletion is two-phase so it cannot invert that order:
// removeRoom may run while room opMu is held and only drops the hub entry plus
// room-scoped transients. commitPairingRoomCleanup then takes tournament opMu
// after room opMu is released. Callers that already hold tournament opMu must
// not call commitPairingRoomCleanup.
// Handler session/rate-limit registries must not be held while reducing.

const (
	zoneDumpDecisionTTL = 90 * time.Second
	zoneDumpGrantTTL    = 2 * time.Minute
	websocketPingEvery  = 25 * time.Second
	websocketPingWait   = 10 * time.Second
	websocketWriteWait  = 10 * time.Second
)

// Handler is the HTTP handler that upgrades to WebSocket and runs a session.
type Handler struct {
	hub                    *Hub
	config                 Config
	retention              *retentionStore
	trustedProxies         []*net.IPNet
	connSeq                uint64 // for connection ids
	activeConnections      int64
	sessionsMu             sync.RWMutex
	sessions               map[string]*Session
	zoneDumpMu             sync.Mutex
	zoneDumpRequests       map[string]zoneDumpRequest
	zoneDumpSeq            uint64
	publicZoneMoveMu       sync.Mutex
	publicZoneMoveRequests map[string]publicZoneMoveRequest
	publicZoneMoveSeq      uint64
	resumeMu               sync.Mutex
	resumeHolds            map[string]resumeHold
	sideboardTimerMu       sync.Mutex
	sideboardTimers        map[string]*time.Timer
	createRateMu           sync.Mutex
	createRates            map[string]createRateWindow
	tournamentCreateRateMu sync.Mutex
	tournamentCreateRates  map[string]createRateWindow
	joinRateMu             sync.Mutex
	joinRates              map[string]createRateWindow
	replayRateMu           sync.Mutex
	replayRates            map[string]createRateWindow
	tournaments            *tournamentRegistry
	// marshalEnvelope, when set, replaces Envelope.Marshal for send/fan-out tests.
	marshalEnvelope func(protocol.Envelope) ([]byte, error)
}

// NewHandler creates a WebSocket handler backed by a fresh hub.
func NewHandler() *Handler {
	handler, err := NewHandlerWithConfig(DefaultConfig())
	if err != nil {
		panic(err)
	}
	return handler
}

// NewHandlerWithConfig creates a bounded handler and optional retention store.
func NewHandlerWithConfig(config Config) (*Handler, error) {
	config = normalizeConfig(config)
	trustedProxies, err := parseTrustedProxies(config.TrustedProxyCIDRs)
	if err != nil {
		return nil, err
	}
	retention, err := newRetentionStore(
		config.RetentionDir, config.RetentionTTL,
		config.RetentionMaxFiles, config.RetentionMaxBytes, time.Now().UTC())
	if err != nil {
		return nil, err
	}
	return &Handler{
		hub: NewHubWithLimits(
			config.MaxRooms, config.MaxConcurrentPasswordChecks),
		config:                 config,
		retention:              retention,
		trustedProxies:         trustedProxies,
		sessions:               make(map[string]*Session),
		zoneDumpRequests:       make(map[string]zoneDumpRequest),
		publicZoneMoveRequests: make(map[string]publicZoneMoveRequest),
		resumeHolds:            make(map[string]resumeHold),
		sideboardTimers:        make(map[string]*time.Timer),
		createRates:            make(map[string]createRateWindow),
		tournamentCreateRates:  make(map[string]createRateWindow),
		joinRates:              make(map[string]createRateWindow),
		replayRates:            make(map[string]createRateWindow),
		tournaments:            newTournamentRegistry(config.MaxTournaments),
	}, nil
}
