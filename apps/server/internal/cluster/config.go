// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// Package cluster coordinates official room placement without owning game state.
package cluster

import (
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"hexproof/server/internal/accounts"
)

var nodePattern = regexp.MustCompile(`^[A-Z0-9]{2,8}$`)

type Node struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	URL    string `json:"url"`
	Weight int    `json:"weight"`
}

type Config struct {
	Realm       string `json:"realm"`
	NodeID      string `json:"nodeId"`
	Coordinator string `json:"coordinator"`
	KeyFile     string `json:"keyFile"`
	Nodes       []Node `json:"nodes"`
	Key         string `json:"-"`
}

func secureURL(value string, websocket bool, realm string) bool {
	u, err := url.Parse(value)
	if err != nil || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" {
		return false
	}
	tls, plain := "https", "http"
	if websocket {
		tls, plain = "wss", "ws"
	}
	return u.Scheme == tls || (u.Scheme == plain && realm != "hexproof-official" && net.ParseIP(u.Hostname()).IsLoopback())
}

func (c Config) Validate() error {
	if !accounts.ValidRealm(c.Realm) || !nodePattern.MatchString(c.NodeID) || len(c.Key) < 32 || len(c.Key) > 4096 || strings.ContainsAny(c.Key, "\r\n") || len(c.Nodes) < 1 || len(c.Nodes) > 16 {
		return errors.New("invalid cluster configuration")
	}
	if c.Coordinator != "" && !secureURL(c.Coordinator, false, c.Realm) {
		return errors.New("cluster coordinator requires HTTPS")
	}
	ids, urls := map[string]bool{}, map[string]bool{}
	for _, n := range c.Nodes {
		if !nodePattern.MatchString(n.ID) || n.Name == "" || len(n.Name) > 128 || !secureURL(n.URL, true, c.Realm) || n.Weight < 1 || n.Weight > 100 || ids[n.ID] || urls[n.URL] {
			return errors.New("invalid cluster node")
		}
		ids[n.ID], urls[n.URL] = true, true
	}
	if !ids[c.NodeID] {
		return errors.New("local node missing from cluster")
	}
	return nil
}

func Load(path string) (*Config, error) {
	if path == "" {
		return nil, nil
	}
	raw, err := os.ReadFile(path)
	if err != nil || len(raw) > 65536 {
		return nil, errors.New("cannot read cluster configuration")
	}
	var c Config
	d := json.NewDecoder(strings.NewReader(string(raw)))
	d.DisallowUnknownFields()
	if err := d.Decode(&c); err != nil || d.Decode(new(any)) != io.EOF {
		return nil, errors.New("invalid cluster configuration JSON")
	}
	keyPath := c.KeyFile
	if !filepath.IsAbs(keyPath) {
		keyPath = filepath.Join(filepath.Dir(path), keyPath)
	}
	key, err := os.ReadFile(keyPath)
	if err != nil || len(key) > 4096 {
		return nil, errors.New("cannot read cluster key file")
	}
	c.Key = strings.TrimSpace(string(key))
	if err := c.Validate(); err != nil {
		return nil, err
	}
	return &c, nil
}

func GlobalCode(node, local string) string { return node + ":" + local }

func SplitCode(code string) (node, local string, ok bool) {
	parts := strings.Split(strings.ToUpper(strings.TrimSpace(code)), ":")
	if len(parts) != 2 || !nodePattern.MatchString(parts[0]) || len(parts[1]) < 1 || len(parts[1]) > 16 {
		return "", "", false
	}
	for _, c := range parts[1] {
		if !(c >= 'A' && c <= 'Z') && !(c >= '0' && c <= '9') {
			return "", "", false
		}
	}
	return parts[0], parts[1], true
}
