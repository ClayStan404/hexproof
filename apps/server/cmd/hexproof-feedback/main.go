// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package main

import (
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/feedback"
)

func main() {
	if err := run(); err != nil {
		log.Print(err)
		os.Exit(1)
	}
}

func run() error {
	configPath := flag.String("config", "/etc/hexproof-feedback/config.json", "receiver configuration")
	version := flag.Bool("version", false, "print version")
	validate := flag.Bool("validate-config", false, "validate configuration without opening the store or connecting")
	adminSocket := flag.String("admin-socket", "", "private receiver administration socket")
	action := flag.String("action", "stats", "admin action: stats, list, inspect, confirm, retry, discard")
	receipt := flag.String("receipt", "", "receipt UUID for an administration action")
	flag.Parse()
	if *version {
		fmt.Printf("hexproof-feedback %s\n", buildinfo.Version)
		return nil
	}
	if *adminSocket != "" {
		return administer(*adminSocket, feedback.AdminRequest{Action: *action, Receipt: *receipt})
	}
	c, err := feedback.LoadConfig(*configPath)
	if err != nil {
		return err
	}
	sender, err := feedback.NewSMTPSender(c.SMTP)
	if err != nil {
		return err
	}
	if *validate {
		fmt.Println("feedback configuration valid")
		return nil
	}
	store, err := feedback.OpenStore(c.DataDir, c.Limits)
	if err != nil {
		return fmt.Errorf("feedback store could not be opened")
	}
	defer store.Close()
	handler := feedback.NewHandler(store, c.Limits, c.TrustedProxyCIDRs)
	public := &http.Server{Addr: c.Listen, Handler: handler, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 45 * time.Second, WriteTimeout: 60 * time.Second, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 16 << 10}
	listener, err := net.Listen("tcp", c.Listen)
	if err != nil {
		return fmt.Errorf("feedback listener unavailable")
	}
	defer listener.Close()
	admin, adminListener, err := feedback.StartAdmin(c.AdminSocket, store)
	if err != nil {
		return fmt.Errorf("feedback administration listener unavailable")
	}
	defer adminListener.Close()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	workerCtx, cancelWorker := context.WithCancel(context.Background())
	defer cancelWorker()
	workerDone := make(chan struct{})
	go func() { defer close(workerDone); feedback.RunOutbox(workerCtx, store, sender) }()
	errors := make(chan error, 2)
	go func() { errors <- public.Serve(listener) }()
	go func() { errors <- admin.Serve(adminListener) }()
	log.Printf("hexproof-feedback %s ready", buildinfo.Version)
	var runErr error
	select {
	case <-ctx.Done():
	case <-errors:
		if ctx.Err() == nil {
			runErr = fmt.Errorf("feedback listener stopped unexpectedly")
		}
	}
	handler.Close()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 55*time.Second)
	defer cancel()
	if public.Shutdown(shutdownCtx) != nil {
		_ = public.Close()
	}
	if admin.Shutdown(shutdownCtx) != nil {
		_ = admin.Close()
	}
	cancelWorker()
	<-workerDone
	return runErr
}

func administer(socket string, request feedback.AdminRequest) error {
	if request.Action == "retry" {
		fmt.Fprintln(os.Stderr, "Explicit retry may deliver a duplicate message.")
	}
	raw, _ := json.Marshal(request)
	transport := &http.Transport{DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "unix", socket)
	}}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 20 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	req, err := http.NewRequest("POST", "http://localhost/admin", bytes.NewReader(raw))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	response, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("feedback administration unavailable")
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		return fmt.Errorf("feedback administration rejected (HTTP %d)", response.StatusCode)
	}
	_, err = io.Copy(os.Stdout, io.LimitReader(response.Body, 16<<20))
	return err
}
