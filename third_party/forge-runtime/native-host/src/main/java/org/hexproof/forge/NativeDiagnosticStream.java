// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import java.io.PrintStream;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.locks.LockSupport;

/** A stalled diagnostic pipe never owns an engine thread or session monitor. */
final class NativeDiagnosticStream {
    static final String PREFIX = "HEXPROOF_DIAG_V1 ";
    private static volatile NativeDiagnosticStream active;
    private final ArrayBlockingQueue<String> observations = new ArrayBlockingQueue<>(32);
    // Independent terminal slots cover the maximum four live shared leases plus bootstrap.
    private final ArrayBlockingQueue<String> terminals = new ArrayBlockingQueue<>(8);
    private final Thread writer;

    private NativeDiagnosticStream(PrintStream output) {
        writer = Thread.ofPlatform().daemon().name("Hexproof-Diagnostics").unstarted(() -> {
            while (!Thread.currentThread().isInterrupted()) {
                String record = terminals.poll();
                if (record == null) record = observations.poll();
                if (record == null) { LockSupport.parkNanos(10_000_000); continue; }
                output.println(PREFIX + record);
                output.flush();
            }
        });
        writer.start();
    }
    static void initialize(PrintStream output) { active = new NativeDiagnosticStream(output); }
    static boolean offer(String record, boolean terminal) {
        NativeDiagnosticStream stream = active;
        if (stream == null) return true;
        boolean accepted = (terminal ? stream.terminals : stream.observations).offer(record);
        if (accepted) LockSupport.unpark(stream.writer);
        return accepted;
    }
    private NativeDiagnosticStream() { throw new AssertionError(); }
}
