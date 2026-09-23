// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package homenode connects fixed operator-owned home hubs to public discovery
// and bounded WebSocket/WebRTC transports. All game authority stays at home.
package homenode

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	"hexproof/server/internal/peerlink"
)

const maxMessageBytes = 4 << 20
const maxControlBytes = 64 << 10

var errUnavailable = errors.New("home node transport unavailable")
var nodePattern = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,62}$`)

type GatewayConfig struct {
	Listen              string            `json:"listen"`
	Nodes               map[string]string `json:"nodes"`
	STUN                []string          `json:"stun,omitempty"`
	TURNURLs            []string          `json:"turnUrls,omitempty"`
	TURNSecret          string            `json:"turnSecret,omitempty"`
	TURNLifetimeSeconds int               `json:"turnLifetimeSeconds,omitempty"`
	RelayOnly           bool              `json:"relayOnly,omitempty"`
	MaxSessions         int               `json:"maxSessions,omitempty"`
	MaxSessionsPerNode  int               `json:"maxSessionsPerNode,omitempty"`
	MaxSessionsPerIP    int               `json:"maxSessionsPerIP,omitempty"`
}

type NodeConfig struct {
	NodeID      string `json:"nodeId"`
	Token       string `json:"token"`
	GatewayURL  string `json:"gatewayUrl"`
	BackendURL  string `json:"backendUrl"`
	HealthURL   string `json:"healthUrl"`
	MaxSessions int    `json:"maxSessions,omitempty"`
}

type ConnectConfig struct {
	URL        string `json:"url"`
	ForceRelay bool   `json:"forceRelay,omitempty"`
	ForceTURN  bool   `json:"forceTURN,omitempty"`
}

func ReadConfig(path string, target any) error {
	f, err := os.Open(path)
	if err != nil {
		return errors.New("cannot read home configuration")
	}
	defer f.Close()
	if info, err := f.Stat(); err != nil || !info.Mode().IsRegular() || info.Size() > maxControlBytes {
		return errors.New("invalid home configuration file")
	}
	d := json.NewDecoder(io.LimitReader(f, maxControlBytes+1))
	d.DisallowUnknownFields()
	if d.Decode(target) != nil {
		return errors.New("invalid home configuration")
	}
	var extra any
	if d.Decode(&extra) != io.EOF {
		return errors.New("invalid home configuration")
	}
	return nil
}

func (c *GatewayConfig) Validate() error {
	if c.Listen == "" {
		c.Listen = "127.0.0.1:57322"
	}
	host, port, err := net.SplitHostPort(c.Listen)
	numericPort, portErr := strconv.Atoi(port)
	if err != nil || !loopback(host) || portErr != nil || numericPort < 1 || numericPort > 65535 {
		return errors.New("gateway listen address must be loopback")
	}
	if len(c.Nodes) == 0 || len(c.Nodes) > 32 {
		return errors.New("configure between one and 32 home nodes")
	}
	for id, token := range c.Nodes {
		if !nodePattern.MatchString(id) || !validSecret(token) {
			return errors.New("invalid node identity or credential")
		}
	}
	if peerlink.ValidateSTUNServers(c.STUN) != nil {
		return errors.New("invalid STUN configuration")
	}
	if (len(c.TURNURLs) > 0) != (c.TURNSecret != "") || (c.TURNSecret != "" && !validSecret(c.TURNSecret)) {
		return errors.New("invalid TURN configuration")
	}
	if len(c.TURNURLs) > 0 && peerlink.ValidateTURNServers([]peerlink.TURNServer{{URLs: c.TURNURLs, Username: "validation", Credential: "validation"}}) != nil {
		return errors.New("invalid TURN URLs")
	}
	if c.RelayOnly && len(c.TURNURLs) == 0 {
		return errors.New("relay-only ICE requires TURN")
	}
	if c.TURNLifetimeSeconds == 0 {
		c.TURNLifetimeSeconds = 24 * 60 * 60
	}
	if c.TURNLifetimeSeconds < 30 || c.TURNLifetimeSeconds > 24*60*60 {
		return errors.New("TURN credential lifetime must be between 30 seconds and 24 hours")
	}
	if c.MaxSessions == 0 {
		c.MaxSessions = 128
	}
	if c.MaxSessionsPerNode == 0 {
		c.MaxSessionsPerNode = 64
	}
	if c.MaxSessionsPerIP == 0 {
		c.MaxSessionsPerIP = 16
	}
	if c.MaxSessions < 1 || c.MaxSessions > 1024 || c.MaxSessionsPerNode < 1 || c.MaxSessionsPerNode > c.MaxSessions || c.MaxSessionsPerIP < 1 || c.MaxSessionsPerIP > c.MaxSessions {
		return errors.New("invalid home connection limits")
	}
	return nil
}

func (c *NodeConfig) Validate() error {
	if !nodePattern.MatchString(c.NodeID) || !validSecret(c.Token) {
		return errors.New("invalid node identity or credential")
	}
	g, err := transportURL(c.GatewayURL)
	if err != nil || g.Path != "/home/register" || g.RawQuery != "" {
		return errors.New("invalid gateway registration URL")
	}
	b, err := url.Parse(c.BackendURL)
	if err != nil || b.Scheme != "ws" || !loopback(b.Hostname()) || b.User != nil || b.Fragment != "" || b.RawQuery != "" {
		return errors.New("backend must be a fixed loopback WebSocket URL")
	}
	h, err := url.Parse(c.HealthURL)
	if err != nil || h.Scheme != "http" || !loopback(h.Hostname()) || h.User != nil || h.Fragment != "" || h.RawQuery != "" {
		return errors.New("health must be a fixed loopback HTTP URL")
	}
	if c.MaxSessions == 0 {
		c.MaxSessions = 64
	}
	if c.MaxSessions < 1 || c.MaxSessions > 1024 {
		return errors.New("invalid node session limit")
	}
	return nil
}

func transportURL(raw string) (*url.URL, error) {
	u, err := url.Parse(raw)
	if err != nil || len(raw) > 2048 || u.Hostname() == "" || u.User != nil || u.Fragment != "" || (u.Scheme != "wss" && (u.Scheme != "ws" || !loopback(u.Hostname()))) {
		return nil, errUnavailable
	}
	return u, nil
}

func homeURL(raw string) (*url.URL, error) {
	u, err := transportURL(raw)
	if err != nil {
		return nil, err
	}
	parts := strings.Split(strings.TrimPrefix(u.Path, "/"), "/")
	if len(parts) != 3 || parts[0] != "home" || !nodePattern.MatchString(parts[1]) || parts[2] != "ws" || !validQuery(u.Query()) {
		return nil, errUnavailable
	}
	return u, nil
}

func validQuery(q url.Values) bool {
	if len(q) == 0 {
		return true
	}
	if len(q) != 1 {
		return false
	}
	for key, values := range q {
		if (key != "engine" && key != "ai") || len(values) != 1 || values[0] != "1" {
			return false
		}
	}
	return true
}

func validSecret(s string) bool {
	if len(s) < 32 || len(s) > 256 {
		return false
	}
	for _, char := range []byte(s) {
		if char <= 32 || char >= 127 {
			return false
		}
	}
	return true
}
func loopback(host string) bool { ip := net.ParseIP(host); return ip != nil && ip.IsLoopback() }
func randomID() string {
	var b [32]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic("random source unavailable")
	}
	return hex.EncodeToString(b[:])
}

func (c GatewayConfig) peerGrant(nodeID, sessionID, binding, token string, offerer, forceTURN bool) peerlink.Config {
	result := peerlink.Config{BindingID: binding, Token: token, Offerer: offerer, STUN: c.STUN, RelayOnly: c.RelayOnly || forceTURN}
	if len(c.TURNURLs) != 0 {
		// Coturn REST credentials are short-lived and isolated per endpoint/session.
		username := fmt.Sprintf("%d:%s:%s:%t", time.Now().Add(time.Duration(c.TURNLifetimeSeconds)*time.Second).Unix(), nodeID, sessionID, offerer)
		mac := hmac.New(sha1.New, []byte(c.TURNSecret))
		_, _ = mac.Write([]byte(username))
		result.TURN = []peerlink.TURNServer{{URLs: c.TURNURLs, Username: username, Credential: base64.StdEncoding.EncodeToString(mac.Sum(nil))}}
	}
	return result
}
