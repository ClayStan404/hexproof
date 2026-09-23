// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"context"
	"fmt"
	"net"
	"sync"
	"sync/atomic"
	"time"

	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/peerlink"
	"hexproof/server/internal/protocol"
	"hexproof/server/internal/rulesengine/forge"
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
	hub                     *Hub
	config                  Config
	retention               *retentionStore
	forgeReplays            *forgeReplayStore
	trustedProxies          []*net.IPNet
	connSeq                 uint64 // for connection ids
	activeConnections       int64
	sessionsMu              sync.RWMutex
	sessions                map[string]*Session
	zoneDumpMu              sync.Mutex
	zoneDumpRequests        map[string]zoneDumpRequest
	zoneDumpSeq             uint64
	publicZoneMoveMu        sync.Mutex
	publicZoneMoveRequests  map[string]publicZoneMoveRequest
	publicZoneMoveSeq       uint64
	resumeMu                sync.Mutex
	resumeHolds             map[string]resumeHold
	sideboardTimerMu        sync.Mutex
	sideboardTimers         map[string]*time.Timer
	roomCreateLimiter       *fixedWindowLimiter
	tournamentCreateLimiter *fixedWindowLimiter
	tournamentChatLimiter   *fixedWindowLimiter
	passwordJoinLimiter     *fixedWindowLimiter
	replayRequestLimiter    *fixedWindowLimiter
	tournaments             *tournamentRegistry
	playerHosts             map[string]*forgehost.Link
	playerBackups           map[string]*playerBackup
	playerPeers             map[string]*playerPeerState
	playerHostStateMu       sync.Mutex
	forgeRuntime            *forge.ProcessConfig
	modelMu                 sync.Mutex
	modelWorkers            map[string]*modelWorker
	forgeNativeAI           bool
	forgePool               *forge.Pool
	forgeMu                 sync.Mutex
	forgeClients            map[forge.Runtime]struct{}
	forgeReservations       map[string]forge.Runtime
	forgeGames              map[string]forgeRoomGame
	forgePromptSequence     atomic.Int64
	forgeClosed             bool
	forgeStarting           chan struct{}
	forgeStartCancel        context.CancelFunc
	forgeRetryAfter         time.Time
	forgeCloseOnce          sync.Once
	forgeCloseErr           error
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
	if err := peerlink.ValidateSTUNServers(config.PeerSTUNServers); err != nil {
		return nil, fmt.Errorf("configure peer STUN servers: %w", err)
	}
	if config.ForgeGamesPerJVM < 1 || config.ForgeGamesPerJVM > 4 {
		return nil, fmt.Errorf("Forge games per JVM must be between 1 and 4")
	}
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
	var forgeRuntime *forge.ProcessConfig
	var forgeNativeAI bool
	var forgePool *forge.Pool
	if config.ForgeRuntime != nil {
		var probe *forge.Client
		var probeErr error
		if config.ForgeGamesPerJVM > 1 {
			forgePool, probeErr = forge.NewPool(*config.ForgeRuntime, config.ForgeGamesPerJVM)
			if probeErr == nil {
				probe, probeErr = forgePool.Acquire(context.Background())
			}
		} else {
			probe, probeErr = forge.Start(context.Background(), *config.ForgeRuntime)
		}
		if probeErr != nil {
			if forgePool != nil {
				_ = forgePool.Close()
			}
			return nil, fmt.Errorf("configure Forge runtime: %w", probeErr)
		}
		forgeNativeAI = probe.SupportsAI()
		if closeErr := probe.Close(); closeErr != nil {
			if forgePool != nil {
				_ = forgePool.Close()
			}
			return nil, fmt.Errorf("close Forge runtime probe: %w", closeErr)
		}
		copy := *config.ForgeRuntime
		copy.Args = append([]string(nil), config.ForgeRuntime.Args...)
		copy.Env = append([]string(nil), config.ForgeRuntime.Env...)
		forgeRuntime = &copy
	}
	return &Handler{
		hub: NewHubWithLimits(
			config.MaxRooms, config.MaxConcurrentPasswordChecks),
		config:                  config,
		retention:               retention,
		forgeReplays:            newForgeReplayStore(config),
		trustedProxies:          trustedProxies,
		sessions:                make(map[string]*Session),
		zoneDumpRequests:        make(map[string]zoneDumpRequest),
		publicZoneMoveRequests:  make(map[string]publicZoneMoveRequest),
		resumeHolds:             make(map[string]resumeHold),
		sideboardTimers:         make(map[string]*time.Timer),
		roomCreateLimiter:       newFixedWindowLimiter(time.Minute, maxRateLimitKeys),
		tournamentCreateLimiter: newFixedWindowLimiter(time.Minute, maxRateLimitKeys),
		tournamentChatLimiter:   newFixedWindowLimiter(time.Minute, maxRateLimitKeys),
		passwordJoinLimiter:     newFixedWindowLimiter(time.Minute, maxRateLimitKeys),
		replayRequestLimiter:    newFixedWindowLimiter(time.Minute, maxRateLimitKeys),
		tournaments:             newTournamentRegistry(config.MaxTournaments),
		playerHosts:             make(map[string]*forgehost.Link),
		playerBackups:           make(map[string]*playerBackup),
		playerPeers:             make(map[string]*playerPeerState),
		forgeRuntime:            forgeRuntime,
		forgeNativeAI:           forgeNativeAI,
		modelWorkers:            make(map[string]*modelWorker),
		forgePool:               forgePool,
		forgeClients:            make(map[forge.Runtime]struct{}),
		forgeReservations:       make(map[string]forge.Runtime),
		forgeGames:              make(map[string]forgeRoomGame),
	}, nil
}

func (h *Handler) forgeRulesAvailable() bool {
	h.forgeMu.Lock()
	defer h.forgeMu.Unlock()
	return !h.forgeClosed && h.forgeRuntime != nil &&
		!time.Now().Before(h.forgeRetryAfter)
}

func (h *Handler) forgeAIAvailable() bool {
	h.forgeMu.Lock()
	defer h.forgeMu.Unlock()
	return !h.forgeClosed && h.forgeRuntime != nil && h.forgeNativeAI && !time.Now().Before(h.forgeRetryAfter)
}
