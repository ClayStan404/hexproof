// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

func TestStartClassifiesExecutableFailuresWithoutPaths(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "private-executable-path")
	_, err := Start(context.Background(), ProcessConfig{Command: missing})
	assertProcessError(t, err, "executable_missing", nil)
	if !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("missing executable lost filesystem cause: %v", err)
	}
	if runtime.GOOS == "windows" {
		return // Windows executable permissions do not follow POSIX mode bits.
	}
	if err := os.WriteFile(missing, []byte("private not an executable"), 0600); err != nil {
		t.Fatal(err)
	}
	_, err = Start(context.Background(), ProcessConfig{Command: missing})
	assertProcessError(t, err, "executable_permission_denied", nil)
	if !errors.Is(err, os.ErrPermission) {
		t.Fatalf("permission failure lost filesystem cause: %v", err)
	}
	if err := os.Chmod(missing, 0700); err != nil {
		t.Fatal(err)
	}
	_, err = Start(context.Background(), ProcessConfig{Command: missing})
	assertProcessError(t, err, "executable_invalid", nil)
}

func TestStartReportsSafeProbeFailuresAndRealExitCodes(t *testing.T) {
	for _, test := range []struct {
		mode string
		code string
		exit *int
	}{
		{"probe-exit", "process_exited", intPointer(23)},
		{"probe-exit-zero", "process_exited", intPointer(0)},
		{"probe-eof", "protocol_eof", nil},
		{"probe-signalled", "process_signalled", intPointer(-1)},
		{"probe-malformed", "protocol_invalid", nil},
		{"probe-oversized", "response_too_large", nil},
		{"probe-rejected", "probe_rejected", nil},
		{"probe-fatal", "probe_rejected", nil},
	} {
		t.Run(test.mode, func(t *testing.T) {
			if test.mode == "probe-signalled" && runtime.GOOS == "windows" {
				t.Skip("Windows process termination has no POSIX signal status")
			}
			config := diagnosticHelperConfig(test.mode)
			config.MaxResponseBytes = 1024
			_, err := Start(context.Background(), config)
			assertProcessError(t, err, test.code, test.exit)
			if test.mode == "probe-exit-zero" {
				if !errors.Is(err, ErrClosed) {
					t.Fatal("clean exit lost ErrClosed compatibility")
				}
			} else if !errors.Is(err, ErrRuntime) {
				t.Fatalf("probe error lost ErrRuntime compatibility: %v", err)
			}
			if test.mode == "probe-oversized" && !errors.Is(err, ErrResponseTooLarge) {
				t.Fatal("oversized response lost ErrResponseTooLarge compatibility")
			}
		})
	}
}

func TestStartPreservesProbeCancellationCauses(t *testing.T) {
	config := diagnosticHelperConfig("probe-hang")
	config.StartTimeout = 50 * time.Millisecond
	_, err := Start(context.Background(), config)
	assertProcessError(t, err, "probe_timeout", nil)
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal("probe timeout lost context cause")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err = Start(ctx, config)
	assertProcessError(t, err, "cancelled", nil)
	if !errors.Is(err, context.Canceled) {
		t.Fatal("probe cancellation lost context cause")
	}
}

func TestReadFailureUsesExitStatusBeforeProfileCleanup(t *testing.T) {
	// Reap a real failed child, then model an unfinished profile cleanup by
	// leaving Done open. Exit classification must not wait on that filesystem
	// work or replace the real status with protocol_eof after 100 ms.
	config := diagnosticHelperConfig("probe-exit")
	command := exec.Command(config.Command, config.Args...)
	command.Env = append(os.Environ(), config.Env...)
	command.Stdin = strings.NewReader("{\"command\":\"reset\"}\n")
	err := command.Run()
	var exit *exec.ExitError
	if !errors.As(err, &exit) || exit.ExitCode() != 23 {
		t.Fatalf("failed to create process exit fixture: %v", err)
	}
	client := &Client{command: command, done: make(chan struct{}), reaped: make(chan struct{}), waitErr: err}
	close(client.reaped)
	result := client.readFailure(io.ErrUnexpectedEOF)
	assertProcessError(t, result, "process_exited", intPointer(23))
	if client.Healthy() {
		t.Fatal("reaped child remains healthy during profile cleanup")
	}
	select {
	case <-client.Done():
		t.Fatal("exit classification prematurely completed profile cleanup")
	default:
	}
}

func diagnosticHelperConfig(mode string) ProcessConfig {
	return ProcessConfig{Command: os.Args[0], Args: []string{"-test.run=TestForgeRuntimeHelperProcess"},
		Env: []string{helperEnvironment + "=" + mode, "GORACE=atexit_sleep_ms=0"}, StartTimeout: 3 * time.Second}
}

func assertProcessError(t *testing.T, err error, code string, exit *int) {
	t.Helper()
	var diagnostic *ProcessError
	if !errors.As(err, &diagnostic) || diagnostic.Code != code {
		t.Fatalf("process failure = %v, want %s", err, code)
	}
	if (diagnostic.ExitCode == nil) != (exit == nil) ||
		(exit != nil && *diagnostic.ExitCode != *exit) {
		t.Fatalf("exit code = %v, want %v", diagnostic.ExitCode, exit)
	}
	for _, secret := range []string{"private", "card", "deck", "token", "secret", "profile"} {
		if strings.Contains(err.Error(), secret) {
			t.Fatalf("process error exposed sensitive output: %v", err)
		}
	}
}
