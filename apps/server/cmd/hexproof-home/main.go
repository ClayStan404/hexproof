// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package main

import (
	"context"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/homenode"
)

func main() { os.Exit(run()) }
func run() int {
	if len(os.Args) == 2 && (os.Args[1] == "-version" || os.Args[1] == "--version") {
		fmt.Println("hexproof-home", buildinfo.Version)
		return 0
	}
	if len(os.Args) < 2 || (os.Args[1] != "gateway" && os.Args[1] != "node") {
		fmt.Fprintln(os.Stderr, "usage: hexproof-home gateway|node -config <file> [-check]")
		return 2
	}
	flags := flag.NewFlagSet("hexproof-home", flag.ContinueOnError)
	path := flags.String("config", "", "protected operator configuration file")
	check := flags.Bool("check", false, "validate configuration without connecting")
	if flags.Parse(os.Args[2:]) != nil || *path == "" || flags.NArg() != 0 {
		return 2
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	if os.Args[1] == "node" {
		var config homenode.NodeConfig
		if err := homenode.ReadConfig(*path, &config); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 2
		}
		if err := config.Validate(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 2
		}
		if *check {
			fmt.Println("home node configuration valid")
			return 0
		}
		if homenode.RunNode(ctx, config) != nil {
			fmt.Fprintln(os.Stderr, "home node stopped")
			return 1
		}
		return 0
	}
	var config homenode.GatewayConfig
	if err := homenode.ReadConfig(*path, &config); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	if err := config.Validate(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	if *check {
		fmt.Println("home gateway configuration valid")
		return 0
	}
	gateway, err := homenode.NewGateway(config)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	defer gateway.Close()
	server := &http.Server{Addr: config.Listen, Handler: gateway, ReadHeaderTimeout: 10 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16 << 10}
	go func() {
		<-ctx.Done()
		gateway.Close()
		limited, stop := context.WithTimeout(context.Background(), 5*time.Second)
		defer stop()
		_ = server.Shutdown(limited)
	}()
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		fmt.Fprintln(os.Stderr, "home gateway listener failed")
		return 1
	}
	return 0
}
