// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package forge

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"time"
)

// ProcessError carries only fixed diagnostic codes and an optional exit code.
// The cause remains available to errors.Is/As, but paths, command arguments,
// engine output and upstream exception text never enter its printable message.
type ProcessError struct {
	Code     string
	ExitCode *int
	cause    error
}

func (err *ProcessError) Error() string { return "forge runtime: " + err.Code }
func (err *ProcessError) Unwrap() error { return err.cause }

func processError(code string, cause error) *ProcessError {
	return &ProcessError{Code: code, cause: cause}
}

func executableError(err error) error {
	code := "executable_start_failed"
	switch {
	case errors.Is(err, os.ErrNotExist), errors.Is(err, exec.ErrNotFound):
		code = "executable_missing"
	case errors.Is(err, os.ErrPermission):
		code = "executable_permission_denied"
	case invalidExecutableError(err):
		code = "executable_invalid"
	}
	return processError(code, err)
}

func probeError(err error) error {
	if errors.Is(err, context.DeadlineExceeded) {
		return processError("probe_timeout", err)
	}
	if errors.Is(err, context.Canceled) {
		return processError("cancelled", err)
	}
	var diagnostic *ProcessError
	if errors.As(err, &diagnostic) {
		return diagnostic
	}
	return processError("probe_rejected", err)
}

// Remember the first failed boundary before killing the process. Otherwise a
// fast Wait can replace a malformed-response diagnosis with our own SIGKILL.
func (client *Client) failProcess(err error) error {
	client.waitMu.Lock()
	if client.boundaryErr == nil {
		client.boundaryErr = err
	}
	client.waitMu.Unlock()
	client.kill()
	return err
}

func (client *Client) readFailure(err error) error {
	if errors.Is(err, ErrResponseTooLarge) {
		return client.failProcess(processError("response_too_large", errors.Join(ErrRuntime, err)))
	}
	// EOF usually precedes Wait by a few scheduler ticks. Give a naturally
	// exiting JVM a bounded reap window, retaining its real exit code instead
	// of attributing the subsequent supervisor kill to an engine crash.
	timer := time.NewTimer(100 * time.Millisecond)
	defer timer.Stop()
	select {
	case <-client.reaped:
		client.invalid.Store(true)
		return client.waitError()
	case <-timer.C:
		return client.failProcess(processError("protocol_eof", errors.Join(ErrRuntime, err)))
	}
}
