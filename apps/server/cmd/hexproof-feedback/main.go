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
	"sync"
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
	var sender feedback.MailSender
	if c.SMTP.Host != "" {
		sender, err = feedback.NewSMTPSender(c.SMTP)
		if err != nil {
			return err
		}
	}
	var publisher *feedback.GitHubPublisher
	if c.Public != nil {
		publisher, err = feedback.NewGitHubPublisher(*c.Public, c.PublicURL)
		if err != nil {
			return err
		}
	}
	var multica *feedback.MulticaWebhook
	if c.Multica != nil {
		multica, err = feedback.NewMulticaWebhook(*c.Multica)
		if err != nil {
			return err
		}
	}
	if *validate {
		fmt.Println("feedback configuration valid")
		return nil
	}
	legacy, err := openLegacyCompatibility(c, sender)
	if err != nil {
		return err
	}
	defer legacy.Close()
	var handler interface {
		http.Handler
		Close()
	}
	var publicStore *feedback.PublicStore
	if c.Public != nil {
		publicStore, err = feedback.OpenPublicStore(c.Public.DataDir, c.Limits)
		if err != nil {
			return fmt.Errorf("public feedback store could not be opened")
		}
		defer publicStore.Close()
		handler = feedback.NewPublicHandler(publicStore, *c.Public, legacy.store, c.Limits, c.TrustedProxyCIDRs)
	} else {
		handler = feedback.NewHandler(legacy.store, c.Limits, c.TrustedProxyCIDRs)
	}
	public := &http.Server{Addr: c.Listen, Handler: handler, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 45 * time.Second, WriteTimeout: 60 * time.Second, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 16 << 10}
	listener, err := net.Listen("tcp", c.Listen)
	if err != nil {
		return fmt.Errorf("feedback listener unavailable")
	}
	defer listener.Close()
	var admin *http.Server
	var adminListener net.Listener
	if legacy.store != nil {
		admin, adminListener, err = feedback.StartAdmin(c.AdminSocket, legacy.store)
		if err != nil {
			return fmt.Errorf("feedback administration listener unavailable")
		}
		defer adminListener.Close()
	}
	var native *http.Server
	var nativeListener net.Listener
	if multica != nil {
		native, nativeListener, err = feedback.StartMulticaNative(c.Multica.Socket, publicStore, multica.Binding(), c.Multica.ProviderPolicyRevision)
		if err != nil {
			return fmt.Errorf("native feedback listener unavailable")
		}
		defer nativeListener.Close()
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	workerCtx, cancelWorker := context.WithCancel(context.Background())
	defer cancelWorker()
	workerDone := make(chan struct{})
	go func() {
		defer close(workerDone)
		var workers sync.WaitGroup
		if legacy.store != nil {
			workers.Add(1)
			go func() { defer workers.Done(); legacy.run(workerCtx) }()
		}
		if publicStore != nil {
			workers.Add(1)
			go func() { defer workers.Done(); feedback.RunPublicOutbox(workerCtx, publicStore, publisher) }()
		}
		if multica != nil {
			workers.Add(1)
			go func() {
				defer workers.Done()
				feedback.RunMulticaOutbox(workerCtx, publicStore, multica, c.Multica.ProviderPolicyRevision)
			}()
		}
		workers.Wait()
	}()
	errors := make(chan error, 3)
	go func() { errors <- public.Serve(listener) }()
	if admin != nil {
		go func() { errors <- admin.Serve(adminListener) }()
	}
	if native != nil {
		go func() { errors <- native.Serve(nativeListener) }()
	}
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
	if admin != nil && admin.Shutdown(shutdownCtx) != nil {
		_ = admin.Close()
	}
	if native != nil && native.Shutdown(shutdownCtx) != nil {
		_ = native.Close()
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
