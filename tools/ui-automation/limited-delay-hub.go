// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// This opt-in native-test fixture starts an isolated hub behind a loopback
// WebSocket proxy. The first Limited submission on each connection delays
// replies for six seconds, allowing visible edits before acknowledgement.
// Build from apps/server to use the repository's pinned WebSocket dependency.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"os/signal"
	"strconv"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/coder/websocket"
)

func relay(ctx context.Context, w http.ResponseWriter, r *http.Request, target string, delay time.Duration) {
	upstream, _, err := websocket.Dial(ctx, target, nil)
	if err != nil {
		http.Error(w, "test hub unavailable", http.StatusBadGateway)
		return
	}
	defer upstream.CloseNow()
	client, err := websocket.Accept(w, r, nil)
	if err != nil {
		return
	}
	defer client.CloseNow()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	client.SetReadLimit(4 << 20)
	upstream.SetReadLimit(4 << 20)
	var release atomic.Pointer[time.Time]
	done := make(chan struct{}, 2)
	copyMessages := func(from, to *websocket.Conn, replies bool) {
		defer func() { done <- struct{}{} }()
		for {
			kind, data, err := from.Read(ctx)
			if err != nil {
				return
			}
			if !replies && release.Load() == nil {
				var envelope struct {
					Type string `json:"type"`
				}
				if json.Unmarshal(data, &envelope) == nil && envelope.Type == "limited.submit_deck" {
					until := time.Now().Add(delay)
					release.Store(&until)
					log.Printf("Delaying first Limited submission replies for %s", delay)
				}
			}
			if until := release.Load(); replies && until != nil && time.Until(*until) > 0 {
				timer := time.NewTimer(time.Until(*until))
				select {
				case <-timer.C:
				case <-ctx.Done():
					timer.Stop()
					return
				}
			}
			if to.Write(ctx, kind, data) != nil {
				return
			}
		}
	}
	go copyMessages(client, upstream, false)
	go copyMessages(upstream, client, true)
	<-done
	cancel()
	client.CloseNow()
	upstream.CloseNow()
	<-done
}

func run() error {
	backend := os.Getenv("HEXPROOF_AUDIT_SERVER_BINARY")
	if backend == "" {
		return fmt.Errorf("set HEXPROOF_AUDIT_SERVER_BINARY to the real local hub executable")
	}
	args := append([]string(nil), os.Args[1:]...)
	bind, port, portIndex := "", 0, -1
	for i := 0; i+1 < len(args); i++ {
		switch args[i] {
		case "-bind":
			bind = args[i+1]
		case "-port":
			port, _ = strconv.Atoi(args[i+1])
			portIndex = i + 1
		}
	}
	if bind != "127.0.0.1" || port <= 0 || port > 65535 || portIndex < 0 {
		return fmt.Errorf("the fixture requires explicit -bind 127.0.0.1 and a valid -port")
	}
	listener, err := net.Listen("tcp", net.JoinHostPort(bind, strconv.Itoa(port)))
	if err != nil {
		return err
	}
	defer listener.Close()
	reservation, err := net.Listen("tcp", net.JoinHostPort(bind, "0"))
	if err != nil {
		return err
	}
	backendPort := reservation.Addr().(*net.TCPAddr).Port
	reservation.Close()
	args[portIndex] = strconv.Itoa(backendPort)
	command := exec.Command(backend, args...)
	command.Stdout, command.Stderr = os.Stdout, os.Stderr
	if err := command.Start(); err != nil {
		return err
	}
	log.Printf("Owned loopback hub PID %d, proxy port %d, backend port %d", command.Process.Pid, port, backendPort)
	hubDone := make(chan error, 1)
	go func() { hubDone <- command.Wait() }()
	defer func() {
		command.Process.Signal(syscall.SIGTERM)
		select {
		case <-hubDone:
		case <-time.After(2 * time.Second):
			command.Process.Kill()
			<-hubDone
		}
	}()
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	address := net.JoinHostPort(bind, strconv.Itoa(backendPort))
	startup := time.NewTimer(10 * time.Second)
	defer startup.Stop()
	for {
		connection, dialErr := net.DialTimeout("tcp", address, 100*time.Millisecond)
		if dialErr == nil {
			connection.Close()
			break
		}
		select {
		case <-ctx.Done():
			return nil
		case <-startup.C:
			return fmt.Errorf("test hub did not listen within 10 seconds")
		case err := <-hubDone:
			hubDone <- err // Leave the completion available for cleanup.
			return fmt.Errorf("test hub exited before startup: %v", err)
		case <-time.After(50 * time.Millisecond):
		}
	}
	backendURL, _ := url.Parse("http://" + address)
	reverse := httputil.NewSingleHostReverseProxy(backendURL)
	server := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/ws" {
			relay(ctx, w, r, "ws://"+address+"/ws", 6*time.Second)
		} else {
			reverse.ServeHTTP(w, r)
		}
	}), ReadHeaderTimeout: 5 * time.Second}
	defer server.Close()
	serveDone := make(chan error, 1)
	go func() { serveDone <- server.Serve(listener) }()
	select {
	case <-ctx.Done():
		return nil
	case err := <-hubDone:
		hubDone <- err
		return fmt.Errorf("test hub exited: %v", err)
	case err := <-serveDone:
		return err
	}
}

func main() {
	if err := run(); err != nil {
		log.Print(err)
		os.Exit(1)
	}
}
