// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import forge.util.ThreadUtil;
import com.google.gson.JsonObject;
import java.io.ByteArrayOutputStream;
import java.io.ObjectOutputStream;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Consumer;
import java.util.function.Supplier;

/** Game-owned dispatch, random source, IDs and mutable caches; never process globals. */
final class NativeExecution implements ThreadUtil.ExecutionContext, AutoCloseable {
    private final Consumer<Throwable> failure;
    final NativeDiagnostics diagnostics;
    private final ExecutorService game;
    private final ExecutorService edt;
    private final ScheduledThreadPoolExecutor delayed;
    private final Map<String, AtomicInteger> ids = new ConcurrentHashMap<>();
    private final Map<String, Object> caches = new ConcurrentHashMap<>();
    private volatile Random random;
    private volatile boolean closed;
    private volatile Thread edtThread;

    NativeExecution(long seed, Consumer<Throwable> failure) {
        this(seed, failure, new NativeDiagnostics("bootstrap"));
    }

    NativeExecution(long seed, Consumer<Throwable> failure, NativeDiagnostics diagnostics) {
        this.failure = failure;
        this.diagnostics = diagnostics;
        random = new Random(seed);
        game = new ScopedExecutor(Executors.newThreadPerTaskExecutor(
                Thread.ofVirtual().name("Game-Hexproof-", 0).factory()), 64, "game_callback");
        edt = new ScopedExecutor(new ThreadPoolExecutor(1, 1, 0, TimeUnit.SECONDS,
                new ArrayBlockingQueue<>(128), action -> {
                    Thread thread = new Thread(action, "Hexproof-Native-EDT");
                    thread.setDaemon(true); edtThread = thread; return thread;
                }), 128, "edt_callback");
        delayed = new ScheduledThreadPoolExecutor(1, action -> {
            Thread thread = new Thread(action, "Hexproof-Native-Delayed");
            thread.setDaemon(true); return thread;
        });
        delayed.setRemoveOnCancelPolicy(true);
        delayed.setExecuteExistingDelayedTasksAfterShutdownPolicy(false);
    }

    ThreadUtil.Scope enter() { return ThreadUtil.enter(this); }
    JsonObject integrity() throws java.io.IOException {
        JsonObject result = new JsonObject();
        try (ByteArrayOutputStream bytes = new ByteArrayOutputStream();
             ObjectOutputStream output = new ObjectOutputStream(bytes)) {
            output.writeObject(random); output.flush();
            result.addProperty("random", Base64.getEncoder().encodeToString(bytes.toByteArray()));
        }
        JsonObject counters = new JsonObject();
        for (var entry : new TreeMap<>(ids).entrySet()) counters.addProperty(entry.getKey(), entry.getValue().get());
        result.add("ids", counters);
        return result;
    }
    boolean isEdt() { return Thread.currentThread() == edtThread; }
    @Override public boolean isClosed() { return closed; }
    void later(Runnable action) {
        if (closed) return;
        try { edt.execute(action); }
        catch (RejectedExecutionException error) { if (!closed) throw error; }
    }
    void andWait(Runnable action) throws Exception {
        if (isEdt()) action.run();
        else edt.submit(action).get(30, TimeUnit.SECONDS);
    }
    @Override public ExecutorService gameExecutor() { return game; }
    @Override public Random random() { return random; }
    @Override public void random(Random value) { random = Objects.requireNonNull(value); }
    @Override public int nextId(String kind) { return ids.computeIfAbsent(kind, ignored -> new AtomicInteger()).incrementAndGet(); }
    @Override public void resetId(String kind, int value) { ids.computeIfAbsent(kind, ignored -> new AtomicInteger()).set(value); }
    @SuppressWarnings("unchecked")
    @Override public <T> T cache(String kind, Supplier<T> create) {
        return (T) caches.computeIfAbsent(kind, ignored -> create.get());
    }
    @Override public Map<String, String> abilityPresentation(String cardName, Map<String, String> parameters) {
        return NativeCardPresentation.hints(cardName, parameters);
    }
    @Override public ScheduledFuture<?> schedule(int milliseconds, Runnable action) {
        if (closed || delayed.getQueue().size() >= 128) throw new RejectedExecutionException("Game timer capacity exceeded");
        var inherited = diagnostics.provenance();
        return delayed.schedule(() -> run(action, "delayed_callback", inherited), milliseconds, TimeUnit.MILLISECONDS);
    }
    @Override public void diagnostic(String stage, Object source, Runnable action) {
        diagnostics.run(stage, source instanceof forge.game.spellability.SpellAbility ability ? ability : null,
                () -> { action.run(); return null; });
    }
    private void run(Runnable action, String stage, List<JsonObject> inherited) {
        if (closed) { cancel(action); return; }
        try (var scope = enter()) {
            diagnostics.withProvenance(inherited, () -> diagnostics.run(stage, null, () -> {
                action.run();
                // A caller-supplied FutureTask swallows its own throwable. Keep its
                // evidence without changing whether/how the caller handles get().
                if (action instanceof FutureTask<?> task && task.isDone() && !task.isCancelled()) {
                    try { task.get(); }
                    catch (ExecutionException error) { diagnostics.remember(error.getCause()); }
                    catch (InterruptedException error) { Thread.currentThread().interrupt(); }
                    catch (CancellationException ignored) { }
                }
                return null;
            }));
        } catch (Throwable error) {
            if (!closed) failure.accept(error);
        }
    }
    private static void cancel(Runnable action) {
        if (action instanceof Future<?> future) future.cancel(true);
    }
    @Override public void close() {
        closed = true;
        delayed.shutdownNow(); edt.shutdownNow(); game.shutdownNow();
    }
    boolean awaitClosed(long milliseconds) throws InterruptedException {
        long end = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(milliseconds);
        for (var executor : List.of(delayed, edt, game))
            if (!executor.awaitTermination(Math.max(0, end - System.nanoTime()), TimeUnit.NANOSECONDS)) return false;
        caches.clear(); ids.clear(); return true;
    }

    private final class ScopedExecutor extends AbstractExecutorService {
        private final ExecutorService delegate;
        private final Semaphore admitted;
        private final String stage;
        private final class Task implements Runnable {
            final Runnable action;
            final List<JsonObject> inherited;
            Task(Runnable action) { this.action = action; inherited = diagnostics.provenance(); }
            @Override public void run() { try { NativeExecution.this.run(action, stage, inherited); } finally { admitted.release(); } }
            void cancel() { NativeExecution.cancel(action); admitted.release(); }
        }
        ScopedExecutor(ExecutorService delegate, int limit, String stage) {
            this.delegate = delegate; admitted = new Semaphore(limit); this.stage = stage;
        }
        @Override protected <T> RunnableFuture<T> newTaskFor(Callable<T> action) {
            return new FutureTask<>(() -> diagnostics.call(action));
        }
        @Override protected <T> RunnableFuture<T> newTaskFor(Runnable action, T result) {
            return newTaskFor(Executors.callable(action, result));
        }
        @Override public void execute(Runnable action) {
            if (closed || !admitted.tryAcquire()) throw new RejectedExecutionException("Game task capacity exceeded");
            try { delegate.execute(new Task(action)); }
            catch (RuntimeException error) { admitted.release(); throw error; }
        }
        @Override public void shutdown() { delegate.shutdown(); }
        @Override public List<Runnable> shutdownNow() {
            List<Runnable> queued = delegate.shutdownNow();
            for (Runnable task : queued) if (task instanceof Task scoped) scoped.cancel();
            return queued;
        }
        @Override public boolean isShutdown() { return delegate.isShutdown(); }
        @Override public boolean isTerminated() { return delegate.isTerminated(); }
        @Override public boolean awaitTermination(long time, TimeUnit unit) throws InterruptedException { return delegate.awaitTermination(time, unit); }
    }
}
