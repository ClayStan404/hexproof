# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Bounded cancellation/cleanup for only subprocess sessions created here."""

from contextlib import contextmanager
import os
import signal
import subprocess
import threading
import time


class ProcessCancelled(Exception):
    def __init__(self, signum):
        self.signum = signum
        super().__init__(f"Interrupted by signal {signum}")


class Cancellation:
    def __init__(self):
        self.event = threading.Event()
        self.signum = None

    def cancel(self, signum, _frame=None):
        self.signum = signum
        self.event.set()

    def check(self):
        if self.event.is_set():
            raise ProcessCancelled(self.signum)


@contextmanager
def cancellation_signals():
    """Install main-thread handlers; workers observe the same cancellation token."""
    token = Cancellation()
    previous = {sig: signal.getsignal(sig) for sig in (signal.SIGINT, signal.SIGTERM)}
    try:
        for sig in previous:
            signal.signal(sig, token.cancel)
        yield token
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def start_owned_process(command, **kwargs):
    """A new session is the sole authority to signal this exact process group."""
    if os.name != "posix":
        raise OSError("Owned process-group isolation requires a POSIX host")
    if "start_new_session" in kwargs:
        raise ValueError("Session isolation is controlled by start_owned_process")
    process = subprocess.Popen(command, start_new_session=True, **kwargs)
    process._hexproof_owned_group = process.pid
    return process


def wait_owned_process(process, timeout, cancellation=None):
    deadline = time.monotonic() + timeout
    while True:
        if cancellation is not None:
            cancellation.check()
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise subprocess.TimeoutExpired(process.args, timeout)
        try:
            return process.wait(timeout=min(.1, remaining))
        except subprocess.TimeoutExpired:
            pass


def stop_owned_process(process, grace_seconds=.3):
    """Stop all members even if the group leader already exited; never broad-kill."""
    group = getattr(process, "_hexproof_owned_group", None)
    if group != process.pid or group <= 1 or group == os.getpgrp():
        raise ValueError("Refusing cleanup of a process group not created here")
    if grace_seconds < 0 or grace_seconds > 10:
        raise ValueError("Cleanup grace must be between zero and ten seconds")
    # Do not infer that an exited leader means its children have exited.
    def send(signum):
        try:
            os.killpg(group, signum)
            return True
        except ProcessLookupError:
            return False

    sent_term = send(signal.SIGTERM)
    deadline = time.monotonic() + grace_seconds
    while sent_term and time.monotonic() < deadline:
        process.poll()  # Reap the leader promptly so it cannot keep a group alive.
        if not send(0):
            break
        time.sleep(.01)
    sent_kill = send(signal.SIGKILL) if send(0) else False
    process.wait(timeout=3)
    return {"group": group, "sentTerm": sent_term, "sentKill": sent_kill,
            "leaderReturnCode": process.returncode}
