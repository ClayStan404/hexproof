// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// hexproof-forge-host is a parent-supervised desktop helper, not a listener.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"sync"
	"syscall"
	"time"

	"hexproof/server/internal/buildinfo"
	"hexproof/server/internal/forgehost"
	"hexproof/server/internal/homenode"
	"hexproof/server/internal/peerlink"
	"hexproof/server/internal/rulesengine/forge"
	"hexproof/server/internal/runtimepkg"
)

var outputMu sync.Mutex
var overlaySHA256 string

func emit(state string, received, total int64) {
	outputMu.Lock()
	defer outputMu.Unlock()
	_ = json.NewEncoder(os.Stdout).Encode(map[string]any{"state": state, "received": received, "total": total,
		"version": buildinfo.Version, "runtimeId": forgehost.RuntimeID})
}

func main() { os.Exit(run()) }
func run() int {
	peerMode := flag.Bool("peer", false, "run the transport-only peer helper without Java")
	homeMode := flag.Bool("home-connect", false, "connect a home hub through direct or relayed transport without Java")
	base := flag.String("runtime-dir", "", "application-private runtime directory")
	prepare := flag.Bool("prepare", false, "download and verify the pinned Java/Forge payload")
	importPack := flag.String("import-pack", "", "install a local .hexproof-forgepack without downloading")
	check := flag.Bool("check", false, "verify an installed runtime without downloading")
	clearCache := flag.Bool("clear-cache", false, "remove cached downloads and unused managed runtimes")
	mirror := flag.String("download-mirror", "", "optional HTTPS directory containing content-addressed runtime archives")
	parentPipe := flag.Bool("parent-pipe", false, "cancel when the supervising parent closes stdin")
	version := flag.Bool("version", false, "print helper and engine compatibility identity")
	flag.Parse()
	modeCount := 0
	for _, enabled := range []bool{*peerMode, *homeMode, *prepare, *check, *clearCache, *importPack != ""} {
		if enabled {
			modeCount++
		}
	}
	if modeCount > 1 {
		reportStep("configuration", "helper", "configuration_invalid")
		emit("configuration_error", 0, 0)
		return 2
	}
	maintenance := *prepare || *check || *clearCache || *importPack != ""
	if *version {
		_ = json.NewEncoder(os.Stdout).Encode(map[string]any{"version": buildinfo.Version, "runtimeId": forgehost.RuntimeID})
		return 0
	}
	if err := initializeProcessGuard(); err != nil {
		reportStep("configuration", "helper", "process_guard_failed")
		emit("process_guard_failed", 0, 0)
		return 2
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	if *homeMode {
		err := homenode.RunConnectPipe(ctx, os.Stdin, os.Stdout)
		if err != nil && ctx.Err() == nil {
			return 1
		}
		return 0
	}
	if *peerMode {
		if err := peerlink.RunPipe(ctx, os.Stdin, os.Stdout); err != nil && ctx.Err() == nil {
			return 1
		}
		return 0
	}
	ctx = runtimepkg.WithDiagnostics(ctx, emitDiagnostic)
	if *base == "" || !filepath.IsAbs(*base) || runtimepkg.Pinned().RuntimeID != forgehost.BaseRuntimeID {
		reportStep("configuration", "helper", "configuration_invalid")
		emit("configuration_error", 0, 0)
		return 2
	}
	input := bufio.NewReaderSize(os.Stdin, 8192)
	var config forgehost.WorkerConfig
	if !maintenance {
		line, err := input.ReadSlice('\n')
		if err != nil || len(line) > 8192 || json.Unmarshal(line, &config) != nil {
			reportStep("configuration", "helper", "configuration_invalid")
			emit("configuration_error", 0, 0)
			return 2
		}
		if config.RuntimeID != forgehost.RuntimeID {
			reportStep("configuration", "helper", "helper_identity_mismatch")
			emit("version_mismatch", 0, 0)
			return 2
		}
	}
	// The pipe is also the parent lease. Closing the UI or cancelling preparation
	// closes stdin, which cancels downloads, network waits and the active JVM.
	peerActions := make(chan forgehost.PeerAction, 1)
	if !maintenance {
		go func() {
			defer cancel()
			scanner := bufio.NewScanner(input)
			scanner.Buffer(make([]byte, 8192), 256<<10)
			for scanner.Scan() {
				var command struct {
					PeerAction *forgehost.PeerAction `json:"peerAction"`
				}
				if json.Unmarshal(scanner.Bytes(), &command) != nil || command.PeerAction == nil {
					return
				}
				select {
				case peerActions <- *command.PeerAction:
				case <-ctx.Done():
					return
				}
			}
		}()
	} else if *parentPipe {
		go func() { _, _ = io.Copy(io.Discard, input); cancel() }()
	}
	if *clearCache {
		emit("cleaning", 0, 0)
		result, err := runtimepkg.ClearCache(ctx, *base)
		if err != nil {
			emitDiagnostic(runtimepkg.ErrorDiagnostic(err, "cleanup", "runtime"))
			emit("cleanup_failed", 0, 0)
			return 1
		}
		emit("cache_cleared", result.FreedBytes, 0)
		return 0
	}
	emit("verifying", 0, 0)
	var installation runtimepkg.Installation
	var err error
	stage := "check"
	if *prepare {
		stage = "prepare"
		reportStep(stage, "runtime", "started")
		_, err = runtimepkg.PrepareWithMirror(ctx, *base, *mirror, emit)
	} else if *importPack != "" {
		stage = "import"
		reportStep(stage, "runtime", "started")
		_, err = runtimepkg.ImportPack(ctx, *base, *importPack, emit)
	}
	var lease io.Closer
	if err == nil {
		if stage != "check" {
			reportStep(stage, "runtime", "completed")
		}
		stage = "check"
		installation, lease, err = runtimepkg.Use(ctx, *base)
	}
	if err != nil {
		emitDiagnostic(runtimepkg.ErrorDiagnostic(err, stage, "runtime"))
		if ctx.Err() != nil {
			emit("cancelled", 0, 0)
		} else if errors.Is(err, runtimepkg.ErrDiskSpace) {
			emit("disk_space", 0, 0)
		} else if errors.Is(err, runtimepkg.ErrPackVersion) {
			emit("pack_version_failed", 0, 0)
		} else if errors.Is(err, runtimepkg.ErrPackPlatform) {
			emit("pack_platform_failed", 0, 0)
		} else if *importPack != "" {
			emit("import_failed", 0, 0)
		} else if *check {
			emit("not_ready", 0, 0)
		} else {
			emit("prepare_failed", 0, 0)
		}
		return 1
	}
	defer lease.Close()
	executable, err := os.Executable()
	if err != nil {
		reportStep("overlay", "helper", "executable_lookup_failed")
		emit("adapter_failed", 0, 0)
		return 1
	}
	overlay, err := runtimepkg.InstallOverlay(ctx, installation,
		filepath.Join(filepath.Dir(executable), "forge-overlay.jar"), overlaySHA256, forgehost.RuntimeID)
	if err != nil {
		emitDiagnostic(runtimepkg.ErrorDiagnostic(err, "overlay", "adapter"))
		emit("adapter_failed", 0, 0)
		return 1
	}
	start := func(startCtx context.Context) (forge.Runtime, error) {
		stage := "jvm_start"
		if maintenance {
			stage = "jvm_probe"
		}
		reportStep(stage, "java", "started")
		process := forge.JavaOverlayProcessConfig(installation.Java, installation.Harness, installation.ForgeHome, overlay)
		process.Args = append([]string{"-Xmx768m", "-XX:+UseSerialGC", "-XX:ActiveProcessorCount=2", "-Djava.awt.headless=true", "-Dfile.encoding=UTF-8"}, process.Args...)
		process.Dir = installation.Root
		runtime, err := forge.Start(startCtx, process)
		if err != nil {
			emitDiagnostic(runtimeStartDiagnostic(err, stage))
			return nil, err
		}
		reportStep(stage, "java", "completed")
		return runtime, nil
	}
	if maintenance {
		// Readiness includes a native adapter probe, not just successful extraction.
		probeCtx, stop := context.WithTimeout(ctx, 45*time.Second)
		defer stop()
		probe, err := start(probeCtx)
		if err != nil {
			emit("start_failed", 0, 0)
			return 1
		}
		_ = probe.Close()
		emit("ready", 0, 0)
		return 0
	}
	emit("ready", 0, 0)
	err = forgehost.Run(ctx, config, start, func(state string) { emit(state, 0, 0) }, forgehost.WorkerPeer{
		Actions: peerActions,
		Reply: func(reply forgehost.PeerReply) {
			outputMu.Lock()
			defer outputMu.Unlock()
			_ = json.NewEncoder(os.Stdout).Encode(map[string]any{"peerReply": reply})
		},
	})
	if err != nil && ctx.Err() == nil {
		reportStep("hosting", "helper", "hosting_failed")
		emit("hosting_failed", 0, 0)
		return 1
	}
	emit("stopped", 0, 0)
	return 0
}
