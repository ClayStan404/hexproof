//go:build engineintegration

// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/pion/webrtc/v4"
	"hexproof/server/internal/peerlink"
)

// These opt-in tests run on explicitly selected machines, never through public
// production rooms. The TLS hub uses a random, private URL namespace and an
// independent in-memory Handler. No application service/config is replaced.
type wanConfig struct {
	Role       string `json:"role"`
	URL        string `json:"url"`
	Token      string `json:"token"`
	Listen     string `json:"listen"`
	Cert       string `json:"cert"`
	Key        string `json:"key"`
	Case       string `json:"case"`
	Mode       string `json:"mode"`
	Runtime    string `json:"runtime"`
	Overlay    string `json:"overlay"`
	Java       string `json:"java"`
	Output     string `json:"output"`
	RequireP2P bool   `json:"requireP2P"`
	Interface  string `json:"interface"`
	PublicICE  bool   `json:"publicICE"`
	BlockICE   bool   `json:"blockICE"`
}

func TestWANPublicCandidateIsolation(t *testing.T) {
	for _, address := range []string{"10.1.2.3", "172.16.10.20", "192.168.1.2", "100.64.12.34",
		"127.0.0.1", "169.254.1.1", "::1", "fe80::1", "fd7a:115c:a1e0::1", "::ffff:100.64.12.34", "local.example"} {
		if publicWANAddress(address) {
			t.Errorf("private or non-IP candidate accepted: %s", address)
		}
	}
	for _, address := range []string{"8.8.8.8", "2606:4700:4700::1111"} {
		if !publicWANAddress(address) {
			t.Errorf("public candidate rejected: %s", address)
		}
	}
	private := "candidate:1 1 udp 2122260223 100.64.12.34 4567 typ host"
	public := "candidate:2 1 udp 1686052607 8.8.8.8 5678 typ srflx raddr 10.1.2.3 rport 1234"
	original := "v=0\r\na=" + private + "\r\na=" + public + "\r\na=end-of-candidates\r\n"
	for _, blocked := range []bool{false, true} {
		report := wanReport{}
		signal := peerlink.Signal{Description: &webrtc.SessionDescription{Type: webrtc.SDPTypeOffer, SDP: original}}
		filtered, keep := publicWANSignal(signal, blocked, &report)
		if !keep || strings.Contains(filtered.Description.SDP, private) || strings.Contains(filtered.Description.SDP, public) == blocked {
			t.Fatal("SDP candidate isolation failed")
		}
		if signal.Description.SDP != original || !strings.Contains(filtered.Description.SDP, "a=end-of-candidates") {
			t.Fatal("candidate filtering changed source SDP or unrelated attributes")
		}
		for _, candidate := range []string{private, public} {
			_, keep := publicWANSignal(peerlink.Signal{Candidate: &webrtc.ICECandidateInit{Candidate: candidate}}, blocked, &report)
			if keep != (candidate == public && !blocked) {
				t.Fatal("trickle candidate isolation failed")
			}
		}
	}
}

func loadWANConfig(t *testing.T) wanConfig {
	t.Helper()
	path := os.Getenv("HEXPROOF_WAN_CONFIG")
	if path == "" {
		t.Skip("explicit WAN qualification config required")
	}
	data, err := os.ReadFile(path)
	var cfg wanConfig
	if err != nil || json.Unmarshal(data, &cfg) != nil || len(cfg.Token) != 64 {
		t.Fatal("invalid private WAN qualification configuration")
	}
	return cfg
}

func (c wanConfig) socketURL() string {
	return "wss" + strings.TrimPrefix(c.URL, "https") + "/" + c.Token + "/ws"
}

func (c wanConfig) coordinate(ctx context.Context, key string, value any) ([]byte, error) {
	method := http.MethodGet
	var body io.Reader
	if value != nil {
		method = http.MethodPut
		data, err := json.Marshal(value)
		if err != nil {
			return nil, err
		}
		body = bytes.NewReader(data)
	}
	request, err := http.NewRequestWithContext(ctx, method, c.URL+"/"+c.Token+"/coord/"+key, body)
	if err != nil {
		return nil, err
	}
	// Never inherit a corporate proxy: the endpoints must use the measured
	// direct Internet route. HTTPS still uses the system certificate trust.
	client := &http.Client{Transport: &http.Transport{Proxy: nil}, Timeout: 5 * time.Second}
	defer client.CloseIdleConnections()
	response, err := client.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusNoContent {
		return nil, nil
	}
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("coordination status %d", response.StatusCode)
	}
	return io.ReadAll(io.LimitReader(response.Body, 64<<10))
}

func TestWANQualificationHub(t *testing.T) {
	cfg := loadWANConfig(t)
	if cfg.Role != "hub" {
		t.Skip("not a hub process")
	}
	config := DefaultConfig()
	config.AllowPlayerHosting = true
	config.MaxPlayerHostedGames = 4
	config.ReconnectWindow = 20 * time.Second
	handler, err := NewHandlerWithConfig(config)
	if err != nil {
		t.Fatal(err)
	}
	defer handler.Close()
	mux := http.NewServeMux()
	prefix := "/" + cfg.Token
	if cfg.PublicICE {
		mux.Handle(prefix+"/ws", nativeWANProxy(t, handler, cfg.BlockICE))
	} else {
		mux.Handle(prefix+"/ws", handler)
	}
	mux.HandleFunc(prefix+"/healthz", handler.ServeHealth)
	var mu sync.Mutex
	records := make(map[string][]byte)
	keys := regexp.MustCompile(`^[a-z0-9-]{1,80}$`)
	mux.HandleFunc(prefix+"/coord/", func(w http.ResponseWriter, r *http.Request) {
		key := strings.TrimPrefix(r.URL.Path, prefix+"/coord/")
		if !keys.MatchString(key) {
			http.Error(w, "invalid key", http.StatusBadRequest)
			return
		}
		mu.Lock()
		defer mu.Unlock()
		w.Header().Set("Cache-Control", "no-store")
		if r.Method == http.MethodPut {
			data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 64<<10))
			if err != nil || !json.Valid(data) || len(records) >= 64 && records[key] == nil {
				http.Error(w, "invalid record", http.StatusBadRequest)
				return
			}
			records[key] = data
		} else if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		data := records[key]
		if data == nil {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write(data)
	})
	server := &http.Server{Addr: cfg.Listen, Handler: mux, ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout: 30 * time.Second, MaxHeaderBytes: 8192}
	defer server.Close()
	t.Log("isolated TLS qualification hub starting")
	if cfg.Cert != "" {
		err = server.ListenAndServeTLS(cfg.Cert, cfg.Key)
	} else if strings.HasPrefix(cfg.Listen, "127.0.0.1:") {
		// An explicitly authorized temporary TLS reverse proxy may front the
		// loopback listener. Never expose cleartext engine traffic publicly.
		err = server.ListenAndServe()
	} else {
		t.Fatal("plain qualification listener must be loopback")
	}
	if err != nil && err != http.ErrServerClosed {
		t.Fatal(err)
	}
}
