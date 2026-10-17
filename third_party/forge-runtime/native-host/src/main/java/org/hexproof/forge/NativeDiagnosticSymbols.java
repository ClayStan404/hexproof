// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import com.google.gson.*;
import java.io.InputStream;
import java.security.MessageDigest;
import java.util.*;

/** Loaded once before gameplay; only packaged code/catalog symbols can cross the diagnostic boundary. */
final class NativeDiagnosticSymbols {
    static final NativeDiagnosticSymbols INSTANCE = load();
    private static final Set<String> JDK_CAUSES = Set.of(
            "java.lang.NullPointerException", "java.lang.IllegalArgumentException", "java.lang.IllegalStateException",
            "java.lang.UnsupportedOperationException", "java.lang.AssertionError", "java.lang.OutOfMemoryError",
            "java.lang.StackOverflowError", "java.lang.IndexOutOfBoundsException", "java.lang.ArithmeticException",
            "java.lang.ClassCastException", "java.lang.RuntimeException", "java.lang.Error", "java.lang.Exception",
            "java.lang.ArrayIndexOutOfBoundsException", "java.lang.NumberFormatException",
            "java.lang.IllegalMonitorStateException", "java.util.NoSuchElementException",
            "java.util.ConcurrentModificationException", "java.util.concurrent.RejectedExecutionException",
            "java.util.concurrent.ExecutionException", "java.util.concurrent.CancellationException",
            "java.util.concurrent.TimeoutException");
    final String id;
    final Map<String, Set<String>> classes;
    final Set<String> apis;
    final Set<String> cardNames;

    private NativeDiagnosticSymbols(String id, Map<String, Set<String>> classes, Set<String> apis, Set<String> names) {
        this.id = id; this.classes = classes; this.apis = apis; cardNames = names;
    }
    private static NativeDiagnosticSymbols load() {
        try (InputStream input = NativeDiagnosticSymbols.class.getResourceAsStream("diagnostic-symbols.json")) {
            if (input == null) return empty();
            byte[] bytes = input.readNBytes(8 * 1024 * 1024 + 1);
            if (bytes.length > 8 * 1024 * 1024) return empty();
            JsonObject root = JsonParser.parseString(new String(bytes, java.nio.charset.StandardCharsets.UTF_8)).getAsJsonObject();
            Map<String, Set<String>> classes = new HashMap<>();
            root.getAsJsonObject("classes").entrySet().forEach(entry -> classes.put(entry.getKey(), strings(entry.getValue().getAsJsonArray())));
            return new NativeDiagnosticSymbols(HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)),
                    Map.copyOf(classes), strings(root.getAsJsonArray("apis")), strings(root.getAsJsonArray("cardNames")));
        } catch (Exception error) { return empty(); }
    }
    private static NativeDiagnosticSymbols empty() { return new NativeDiagnosticSymbols("", Map.of(), Set.of(), Set.of()); }
    private static Set<String> strings(JsonArray values) {
        Set<String> result = new HashSet<>();
        for (JsonElement value : values) result.add(value.getAsString());
        return Set.copyOf(result);
    }
    String cause(Class<?> type) {
        String name = type.getName();
        return JDK_CAUSES.contains(name) || classes.containsKey(name) ? name : "unknown";
    }
    JsonObject frame(StackTraceElement frame) {
        String name = frame.getClassName(), method = frame.getMethodName();
        Set<String> methods = classes.get(name);
        if (methods == null || !methods.contains(method)) return null;
        JsonObject result = new JsonObject();
        result.addProperty("className", name); result.addProperty("methodName", method);
        result.addProperty("line", Math.max(-1, Math.min(1000000, frame.getLineNumber())));
        return result;
    }
}
