// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package homenode

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"
)

type Gateway struct {
	config   GatewayConfig
	mu       sync.Mutex
	nodes    map[string]*registeredNode
	sessions map[string]*gatewaySession
	rates    map[string]admissionWindow
	closed   bool
}
type admissionWindow struct {
	start time.Time
	count int
}
type registeredNode struct {
	id       string
	conn     *websocket.Conn
	writer   *controlWriter
	cancel   context.CancelFunc
	health   json.RawMessage
	healthAt time.Time
}
type gatewaySession struct {
	id, token, ip string
	node          *registeredNode
	ctx           context.Context
	cancel        context.CancelFunc
	attached      chan *websocket.Conn
	claimed       bool
}

func NewGateway(config GatewayConfig) (*Gateway, error) {
	if err := config.Validate(); err != nil {
		return nil, err
	}
	return &Gateway{config: config, nodes: make(map[string]*registeredNode), sessions: make(map[string]*gatewaySession), rates: make(map[string]admissionWindow)}, nil
}

func (g *Gateway) Close() {
	g.mu.Lock()
	g.closed = true
	for _, session := range g.sessions {
		session.cancel()
	}
	for _, node := range g.nodes {
		node.cancel()
		_ = node.conn.CloseNow()
	}
	g.mu.Unlock()
}

func (g *Gateway) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	switch r.URL.Path {
	case "/home/register":
		g.register(w, r)
		return
	case "/home/attach":
		g.attach(w, r)
		return
	}
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/"), "/")
	if len(parts) != 3 || parts[0] != "home" || !nodePattern.MatchString(parts[1]) {
		http.NotFound(w, r)
		return
	}
	if parts[2] == "healthz" {
		g.health(w, r, parts[1])
		return
	}
	if parts[2] != "ws" && parts[2] != "signal" {
		http.NotFound(w, r)
		return
	}
	g.serveClient(w, r, parts[1], parts[2])
}

func (g *Gateway) register(w http.ResponseWriter, r *http.Request) {
	id := r.Header.Get("X-Hexproof-Node")
	secret, exists := g.config.Nodes[id]
	if r.URL.RawQuery != "" || !exists || !secretEqual(r.Header.Get("Authorization"), "Bearer "+secret) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	c, err := websocket.Accept(w, r, &websocket.AcceptOptions{CompressionMode: websocket.CompressionDisabled})
	if err != nil {
		return
	}
	defer c.CloseNow()
	c.SetReadLimit(maxControlBytes)
	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	node := &registeredNode{id: id, conn: c, cancel: cancel}
	node.writer = newControlWriter(ctx, cancel, c)
	g.mu.Lock()
	if g.closed {
		g.mu.Unlock()
		return
	}
	if old := g.nodes[id]; old != nil {
		old.cancel()
		_ = old.conn.CloseNow()
		for _, session := range g.sessions {
			if session.node == old {
				session.cancel()
			}
		}
	}
	g.nodes[id] = node
	g.mu.Unlock()
	defer func() {
		g.mu.Lock()
		if g.nodes[id] == node {
			delete(g.nodes, id)
		}
		for _, session := range g.sessions {
			if session.node == node {
				session.cancel()
			}
		}
		g.mu.Unlock()
	}()
	go heartbeat(ctx, c)
	for {
		message, err := readFrame(ctx, c)
		var report healthReport
		if err != nil || message.Type != "health" || len(message.Health) > 4096 || json.Unmarshal(message.Health, &report) != nil || !report.OK {
			return
		}
		capabilities, ok := canonicalCapabilities(report.Capabilities)
		if !ok {
			return
		}
		report.Capabilities = capabilities
		health, _ := json.Marshal(report)
		g.mu.Lock()
		node.health = append(node.health[:0], health...)
		node.healthAt = time.Now()
		g.mu.Unlock()
	}
}

func (g *Gateway) health(w http.ResponseWriter, r *http.Request, id string) {
	if r.URL.RawQuery != "" {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}
	g.mu.Lock()
	node := g.nodes[id]
	var health []byte
	if !g.closed && node != nil && time.Since(node.healthAt) <= 30*time.Second {
		health = append([]byte(nil), node.health...)
	}
	g.mu.Unlock()
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	var report healthReport
	if len(health) == 0 || json.Unmarshal(health, &report) != nil || !report.OK {
		w.WriteHeader(http.StatusServiceUnavailable)
		_, _ = w.Write([]byte("unavailable\n"))
		return
	}
	w.Header().Set("X-Hexproof-Capabilities", string(report.Capabilities))
	_, _ = w.Write([]byte("ok\n"))
}

func (g *Gateway) reserve(ctx context.Context, id, ip string) *gatewaySession {
	g.mu.Lock()
	defer g.mu.Unlock()
	node := g.nodes[id]
	if g.closed || node == nil || time.Since(node.healthAt) > 30*time.Second || len(g.sessions) >= g.config.MaxSessions {
		return nil
	}
	var nodeCount, ipCount int
	for _, session := range g.sessions {
		if session.node == node {
			nodeCount++
		}
		if session.ip == ip {
			ipCount++
		}
	}
	if nodeCount >= g.config.MaxSessionsPerNode || ipCount >= g.config.MaxSessionsPerIP {
		return nil
	}
	now := time.Now()
	if len(g.rates) >= 4096 {
		for key, bucket := range g.rates {
			if now.Sub(bucket.start) >= time.Minute {
				delete(g.rates, key)
			}
		}
	}
	bucket, exists := g.rates[ip]
	if !exists && len(g.rates) >= 4096 {
		return nil
	}
	if now.Sub(bucket.start) >= time.Minute {
		bucket = admissionWindow{start: now}
	}
	if bucket.count >= 30 {
		return nil
	}
	bucket.count++
	g.rates[ip] = bucket
	owned, cancel := context.WithCancel(ctx)
	session := &gatewaySession{id: randomID(), token: randomID(), ip: ip, node: node, ctx: owned, cancel: cancel, attached: make(chan *websocket.Conn, 1)}
	g.sessions[session.id] = session
	return session
}

func (g *Gateway) release(session *gatewaySession) {
	session.cancel()
	g.mu.Lock()
	delete(g.sessions, session.id)
	g.mu.Unlock()
	select {
	case conn := <-session.attached:
		_ = conn.CloseNow()
	default:
	}
}

func (g *Gateway) serveClient(w http.ResponseWriter, r *http.Request, nodeID, mode string) {
	query := r.URL.Query()
	forceTURN := mode == "signal" && query.Get("forceTURN") == "1"
	if mode == "signal" {
		if values, exists := query["forceTURN"]; exists && (len(values) != 1 || values[0] != "1") {
			http.Error(w, "invalid transport request", http.StatusBadRequest)
			return
		}
		query.Del("forceTURN")
	}
	if !validQuery(query) || (mode == "signal" && len(query) != 0) || (forceTURN && len(g.config.TURNURLs) == 0) {
		http.Error(w, "invalid transport request", http.StatusBadRequest)
		return
	}
	session := g.reserve(r.Context(), nodeID, remoteIP(r))
	if session == nil {
		http.Error(w, "node unavailable or connection limit reached", http.StatusServiceUnavailable)
		return
	}
	defer g.release(session)
	client, err := websocket.Accept(w, r, &websocket.AcceptOptions{CompressionMode: websocket.CompressionDisabled})
	if err != nil {
		return
	}
	defer client.CloseNow()
	client.SetReadLimit(int64(gameFrameLimit(query)))
	go heartbeat(session.ctx, client)
	open := frame{Type: "open", ID: session.id, Token: session.token, Mode: mode, Query: query.Encode(), RemoteIP: session.ip}
	if mode == "signal" {
		client.SetReadLimit(maxControlBytes)
		binding, token := randomID(), randomID()
		nodePeer := g.config.peerGrant(nodeID, session.id, binding, token, false, forceTURN)
		clientPeer := g.config.peerGrant(nodeID, session.id, binding, token, true, forceTURN)
		open.Peer = &nodePeer
		if writeFrame(session.ctx, client, frame{Type: "grant", Peer: &clientPeer}) != nil {
			return
		}
	}
	if !session.node.writer.send(open) {
		return
	}
	timer := time.NewTimer(12 * time.Second)
	defer timer.Stop()
	select {
	case node := <-session.attached:
		if mode == "signal" {
			bridge(session.ctx, client, node, maxControlBytes)
		} else {
			bridge(session.ctx, client, node, gameFrameLimit(query))
		}
	case <-timer.C:
	case <-session.ctx.Done():
	}
}

func (g *Gateway) attach(w http.ResponseWriter, r *http.Request) {
	id := r.Header.Get("X-Hexproof-Session")
	g.mu.Lock()
	session := g.sessions[id]
	valid := session != nil && !session.claimed && g.nodes[session.node.id] == session.node && session.ctx.Err() == nil &&
		r.Header.Get("X-Hexproof-Node") == session.node.id && secretEqual(r.Header.Get("Authorization"), "Bearer "+session.token)
	if valid {
		session.claimed = true
	}
	g.mu.Unlock()
	if !valid || r.URL.RawQuery != "" {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{CompressionMode: websocket.CompressionDisabled})
	if err != nil {
		session.cancel()
		return
	}
	defer conn.CloseNow()
	conn.SetReadLimit(16 << 20)
	select {
	case session.attached <- conn:
	case <-session.ctx.Done():
		return
	}
	<-session.ctx.Done()
}

func secretEqual(a, b string) bool {
	return len(a) == len(b) && subtle.ConstantTimeCompare([]byte(a), []byte(b)) == 1
}

func remoteIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	ip := net.ParseIP(host)
	if ip == nil {
		return "unknown"
	}
	if ip.IsLoopback() {
		// The loopback nginx ingress must overwrite these headers.
		forwarded := r.Header.Get("X-Real-IP")
		if forwarded == "" {
			forwarded = strings.TrimSpace(strings.Split(r.Header.Get("X-Forwarded-For"), ",")[0])
		}
		if parsed := net.ParseIP(forwarded); parsed != nil {
			return parsed.String()
		}
	}
	return ip.String()
}
