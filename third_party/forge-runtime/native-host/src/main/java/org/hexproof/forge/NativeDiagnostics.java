// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import forge.game.card.Card;
import forge.game.spellability.SpellAbility;
import forge.game.zone.ZoneType;
import java.nio.charset.StandardCharsets;
import java.lang.ref.WeakReference;
import java.util.*;
import java.util.concurrent.Callable;
import java.util.function.Supplier;

/** Bounded immutable observations. Capturing a throwable does not make it terminal. */
final class NativeDiagnostics {
    private final String producerId = UUID.randomUUID().toString();
    private static final long STARTED = System.nanoTime();
    private static final Set<String> STAGES = Set.of("effect", "decision", "game_callback", "edt_callback",
            "delayed_callback", "submitted_task", "rpc", "bootstrap", "input_boundary_timeout");
    private static final Set<ZoneType> PUBLIC_ZONES = Set.of(ZoneType.Battlefield, ZoneType.Stack,
            ZoneType.Graveyard, ZoneType.Exile, ZoneType.Command);
    private final NativeDiagnosticSymbols symbols = NativeDiagnosticSymbols.INSTANCE;
    private final String sessionId;
    private final ThreadLocal<List<JsonObject>> active = ThreadLocal.withInitial(List::of);
    private final LinkedHashMap<WeakReference<Throwable>, List<JsonObject>> candidates = new LinkedHashMap<>();
    private final ArrayDeque<JsonObject> events = new ArrayDeque<>();
    private long sequence;
    private long serial;
    private int dropped;
    private int omittedSpans;
    private long lastEmission;
    private JsonObject terminal;

    NativeDiagnostics(String sessionId) { this.sessionId = sessionId; }
    String producerId() { return producerId; }
    List<JsonObject> provenance() { return active.get(); }
    <T> T withProvenance(List<JsonObject> inherited, Supplier<T> action) {
        List<JsonObject> previous = active.get(); active.set(inherited);
        try { return action.get(); } finally { active.set(previous); }
    }
    <T> T run(String stage, SpellAbility ability, Supplier<T> action) {
        List<JsonObject> previous = active.get();
        List<JsonObject> next = enter(stage, ability, previous);
        active.set(next);
        try { return action.get(); }
        catch (RuntimeException | Error error) { capture(error, next); throw error; }
        finally { event(next.isEmpty() ? null : next.getLast(), "effect_exit", previous); active.set(previous); }
    }
    <T> T call(Callable<T> action) throws Exception {
        List<JsonObject> previous = active.get();
        List<JsonObject> next = enter("submitted_task", null, previous); active.set(next);
        try { return action.call(); }
        catch (Exception | Error error) { capture(error, next); throw error; }
        finally { active.set(previous); }
    }
    private List<JsonObject> enter(String stage, SpellAbility ability, List<JsonObject> previous) {
        try {
            JsonObject span = new JsonObject();
            synchronized (this) { span.addProperty("id", ++serial); }
            span.addProperty("parentId", previous.isEmpty() ? 0 : previous.getLast().get("id").getAsLong());
            span.addProperty("stage", STAGES.contains(stage) ? stage : "rpc");
            if (ability != null) {
                String api = ability.getApi() == null ? "" : ability.getApi().name();
                if (symbols.apis.contains(api)) span.addProperty("api", api);
                JsonObject source = publicSource(ability.getHostCard());
                if (source != null) span.add("source", source);
            }
            List<JsonObject> next = new ArrayList<>(previous);
            if (next.size() >= 8) { next.removeFirst(); synchronized (this) { omittedSpans++; } }
            next.add(span);
            event(span, stage.equals("effect") ? "effect_enter" : stage.equals("decision") ? "decision" : "callback", next);
            return List.copyOf(next);
        } catch (Throwable ignored) { return previous; }
    }
    private JsonObject publicSource(Card card) {
        if (card == null || !NativeSnapshot.canSeeIdentity(card, null)) return null;
        ZoneType zone = card.getZone() == null ? null : card.getZone().getZoneType();
        if (!PUBLIC_ZONES.contains(zone)) return null;
        JsonObject identity = NativeSnapshot.identity(card);
        if (!symbols.cardNames.contains(identity.get("name").getAsString())) return null;
        JsonObject result = new JsonObject();
        result.addProperty("objectId", NativeSnapshot.cardId(card));
        result.addProperty("incarnation", Long.toString(card.getGameTimestamp()));
        synchronized (this) { result.addProperty("observationSequence", sequence + 1); }
        result.addProperty("zone", zone.name().toLowerCase(Locale.ROOT));
        result.addProperty("disclosure", "public_zone"); result.add("card", identity);
        return result;
    }
    private synchronized void event(JsonObject span, String kind, List<JsonObject> contextSpans) {
        try {
            if (span == null) return;
            JsonObject event = new JsonObject(); event.addProperty("sequence", ++sequence);
            event.addProperty("kind", kind); event.addProperty("spanId", span.get("id").getAsLong());
            event.add("stage", span.get("stage")); if (span.has("api")) event.add("api", span.get("api"));
            if (events.size() == 128) { events.removeFirst(); dropped++; }
            events.addLast(event);
            long now = System.nanoTime();
            if (terminal == null && now - lastEmission >= 100_000_000) {
                lastEmission = now;
                JsonObject context = base("context", span.get("stage").getAsString(), contextSpans);
                context.add("causes", new JsonArray());
                if (!NativeDiagnosticStream.offer(bound(context).toString(), false)) dropped++;
            }
        } catch (Throwable ignored) { dropped++; }
    }
    void remember(Throwable error) { capture(error, active.get()); }
    private synchronized void capture(Throwable error, List<JsonObject> spans) {
        try {
            if (find(error) != null) return;
            candidates.keySet().removeIf(reference -> reference.get() == null);
            if (candidates.size() == 64) candidates.pollFirstEntry();
            candidates.put(new WeakReference<>(error), spans);
        } catch (Throwable ignored) { }
    }
    private List<JsonObject> find(Throwable error) {
        Set<Throwable> seen = Collections.newSetFromMap(new IdentityHashMap<>());
        for (int i = 0; error != null && i < 8 && seen.add(error); i++, error = error.getCause()) {
            for (var entry : candidates.entrySet()) if (entry.getKey().get() == error) return entry.getValue();
        }
        return null;
    }
    synchronized void terminal(Throwable error, String boundary) {
        if (terminal != null) return;
        try {
            List<JsonObject> site = find(error);
            if (site == null) site = active.get();
            String kind = boundary.equals("input_boundary_timeout") ? "execution_timeout" : "engine_exception";
            JsonArray causes = new JsonArray(); int omittedFrames = 0, omittedCauses = 0;
            List<Throwable> chain = new ArrayList<>();
            Set<Throwable> seen = Collections.newSetFromMap(new IdentityHashMap<>());
            Throwable current = error;
            while (current != null && chain.size() < 16 && seen.add(current)) {
                if (current instanceof OutOfMemoryError || current instanceof StackOverflowError) kind = "resource_exhausted";
                chain.add(current); current = current.getCause();
            }
            if (current != null) omittedCauses++;
            while (chain.size() > 4) { chain.remove(1); omittedCauses++; }
            int framesPerCause = 32 / Math.max(1, chain.size());
            for (Throwable causeValue : chain) {
                JsonObject cause = new JsonObject(); cause.addProperty("className", symbols.cause(causeValue.getClass()));
                JsonArray frames = new JsonArray();
                StackTraceElement[] rawFrames = causeValue.getStackTrace();
                for (int index = 0; index < Math.min(128, rawFrames.length); index++) {
                    JsonObject frame = symbols.frame(rawFrames[index]);
                    if (frame == null || frames.size() == framesPerCause) { omittedFrames++; continue; }
                    frames.add(frame);
                }
                omittedFrames += Math.max(0, rawFrames.length - 128);
                cause.add("frames", frames); causes.add(cause);
            }
            String actualBoundary = site.isEmpty() ? boundary : site.getLast().get("stage").getAsString();
            JsonObject value = base(kind, actualBoundary, site);
            value.addProperty("attribution", site.isEmpty() ? "unknown" : "execution_site");
            value.add("causes", causes); value.addProperty("omittedFrames", omittedFrames);
            value.addProperty("omittedCauses", omittedCauses);
            terminal = bound(value);
            NativeDiagnosticStream.offer(terminal.toString(), true);
        } catch (Throwable ignored) { /* Severe allocation failure may leave no safe capsule. */ }
    }
    synchronized JsonObject failureInfo() { return terminal == null ? null : terminal.deepCopy(); }
    private JsonObject base(String kind, String boundary, List<JsonObject> spans) {
        JsonObject value = new JsonObject(); value.addProperty("schemaVersion", 1);
        value.addProperty("producerId", producerId); value.addProperty("sessionId", sessionId);
        value.addProperty("sequence", ++sequence); value.addProperty("elapsedMs", (System.nanoTime() - STARTED) / 1_000_000);
        value.addProperty("kind", kind); value.addProperty("boundary", STAGES.contains(boundary) ? boundary : "rpc");
        value.addProperty("attribution", spans.isEmpty() ? "unknown" : "resolution_context");
        value.addProperty("symbolIndexId", symbols.id);
        JsonArray stack = new JsonArray(); spans.forEach(span -> stack.add(span.deepCopy())); value.add("spans", stack);
        JsonArray tail = new JsonArray(); events.stream().skip(Math.max(0, events.size() - 32)).forEach(tail::add);
        value.add("events", tail); value.addProperty("droppedEvents", dropped + Math.max(0, events.size() - 32));
        value.addProperty("omittedSpans", omittedSpans); value.addProperty("omittedFrames", 0); value.addProperty("omittedCauses", 0);
        return value;
    }
    private JsonObject bound(JsonObject value) {
        while (value.toString().getBytes(StandardCharsets.UTF_8).length > 16 * 1024) {
            JsonArray tail = value.getAsJsonArray("events"), spans = value.getAsJsonArray("spans");
            if (!tail.isEmpty()) { tail.remove(0); value.addProperty("droppedEvents", value.get("droppedEvents").getAsInt() + 1); continue; }
            boolean removed = false;
            JsonArray causes = value.getAsJsonArray("causes");
            if (causes != null) for (int i = causes.size() - 1; i >= 0; i--) {
                JsonArray frames = causes.get(i).getAsJsonObject().getAsJsonArray("frames");
                if (!frames.isEmpty()) { frames.remove(frames.size() - 1); removed = true; break; }
            }
            if (removed) { value.addProperty("omittedFrames", value.get("omittedFrames").getAsInt() + 1); continue; }
            if (spans.size() > 1) { spans.remove(0); value.addProperty("omittedSpans", value.get("omittedSpans").getAsInt() + 1); continue; }
            return null;
        }
        return value;
    }
}
