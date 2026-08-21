// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Command hexproof-server is the Hexproof room hub. It serves WebSocket
// sessions at /ws and manages room state via the room reducer (P1).
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/server"
)

func main() {
	showVersion := flag.Bool("version", false, "print version and exit")
	bind := flag.String("bind", "127.0.0.1", "bind address")
	port := flag.Int("port", 57320, "listen port")
	reconnectWindow := flag.Duration("reconnect-window", 3*time.Minute,
		"network-drop seat hold duration")
	helloTimeout := flag.Duration("hello-timeout", 10*time.Second,
		"maximum time to complete session.hello")
	retentionTTL := flag.Duration("retention-ttl", 7*24*time.Hour,
		"retained match expiration duration")
	retentionDir := flag.String("retention-dir", "data/retained",
		"operator-only retained match directory (empty disables storage)")
	retentionMaxFiles := flag.Int("retention-max-files", 512,
		"maximum retained match files")
	retentionMaxBytes := flag.Int64("retention-max-bytes", 512<<20,
		"maximum retained match bytes")
	replayPageSize := flag.Int("replay-page-size", 50,
		"maximum replay summaries per response")
	trustedProxies := flag.String("trusted-proxies", "127.0.0.1/32,::1/128",
		"comma-separated proxy CIDRs allowed to supply X-Forwarded-For")
	maxRooms := flag.Int("max-rooms", 256, "maximum live rooms")
	maxTournaments := flag.Int("max-tournaments", 64, "maximum live tournaments")
	maxConnections := flag.Int64("max-connections", 1024,
		"maximum simultaneous WebSocket connections")
	maxMessageBytes := flag.Int64("max-message-bytes", 1<<20,
		"maximum inbound WebSocket message size")
	messagesPerSecond := flag.Int("messages-per-second", 60,
		"per-connection inbound message rate")
	replayRequestsPerMinute := flag.Int("replay-requests-per-minute", 30,
		"per-IP replay list/load request rate")
	roomCreatesPerMinute := flag.Int("room-creates-per-minute", 6,
		"per-IP room creation rate")
	tournamentCreatesPerMinute := flag.Int("tournament-creates-per-minute", 3,
		"per-IP tournament creation rate")
	tournamentClosedTTL := flag.Duration("tournament-closed-ttl", 24*time.Hour,
		"retention for closed tournaments with no connected viewers")
	tournamentInactiveTTL := flag.Duration("tournament-inactive-ttl", 2*time.Hour,
		"retention for registration tournaments with no connected sessions")
	tournamentAbandonedTTL := flag.Duration("tournament-abandoned-ttl", 24*time.Hour,
		"retention for running tournaments with no connected sessions or pairing rooms")
	passwordJoinsPerMinute := flag.Int("password-joins-per-minute", 20,
		"per-IP protected-room join rate")
	maxConcurrentPasswordChecks := flag.Int("max-concurrent-password-checks", 8,
		"maximum concurrent bcrypt password checks")
	flag.Parse()
	if *showVersion {
		fmt.Fprintf(os.Stdout, "hexproof-server %s\n", buildinfo.Version)
		return
	}

	handler, err := server.NewHandlerWithConfig(server.Config{
		ReconnectWindow:             *reconnectWindow,
		HelloTimeout:                *helloTimeout,
		RetentionTTL:                *retentionTTL,
		RetentionDir:                *retentionDir,
		RetentionMaxFiles:           *retentionMaxFiles,
		RetentionMaxBytes:           *retentionMaxBytes,
		ReplayPageSize:              *replayPageSize,
		TrustedProxyCIDRs:           splitCommaSeparated(*trustedProxies),
		MaxRooms:                    *maxRooms,
		MaxTournaments:              *maxTournaments,
		MaxConnections:              *maxConnections,
		MaxMessageBytes:             *maxMessageBytes,
		MessagesPerSecond:           *messagesPerSecond,
		ReplayRequestsPerMinute:     *replayRequestsPerMinute,
		RoomCreatesPerMinute:        *roomCreatesPerMinute,
		TournamentCreatesPerMinute:  *tournamentCreatesPerMinute,
		TournamentClosedTTL:         *tournamentClosedTTL,
		TournamentInactiveTTL:       *tournamentInactiveTTL,
		TournamentAbandonedTTL:      *tournamentAbandonedTTL,
		PasswordJoinsPerMinute:      *passwordJoinsPerMinute,
		MaxConcurrentPasswordChecks: *maxConcurrentPasswordChecks,
	})
	if err != nil {
		log.Fatalf("hexproof-server: configure: %v", err)
	}

	mux := http.NewServeMux()
	// Ops/tunnel health checks (Cloudflare / curl). Not part of the game protocol.
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok\n"))
	})
	mux.Handle("/ws", handler)

	addr := fmt.Sprintf("%s:%d", *bind, *port)
	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
	}
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		log.Fatalf("hexproof-server: listen %s: %v", addr, err)
	}

	// Graceful shutdown on SIGINT/SIGTERM (resolves review #6: no accept-loop
	// error spam when the listener closes).
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-stop
		log.Printf("hexproof-server: shutting down")
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(ctx)
	}()

	// Print readiness only after the socket has been bound successfully. This
	// keeps deployment scripts from observing a false-positive ready line when
	// the configured address is unavailable.
	fmt.Fprintf(os.Stdout,
		"hexproof-server %s listening on %s (ws path /ws, protocol hexproof.v1)\n",
		buildinfo.Version, listener.Addr())
	log.Printf("hexproof-server %s ready on %s", buildinfo.Version, listener.Addr())

	if err := srv.Serve(listener); err != nil && err != http.ErrServerClosed {
		log.Fatalf("hexproof-server: %v", err)
	}
	log.Printf("hexproof-server: stopped")
}

func splitCommaSeparated(value string) []string {
	if value == "" {
		return []string{}
	}
	parts := strings.Split(value, ",")
	for index := range parts {
		parts[index] = strings.TrimSpace(parts[index])
	}
	return parts
}
