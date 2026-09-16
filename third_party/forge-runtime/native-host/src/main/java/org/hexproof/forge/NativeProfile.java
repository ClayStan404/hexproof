// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import java.io.IOException;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;

/** A JVM owns one generated profile; asset paths never become writable state. */
final class NativeProfile {
    private NativeProfile() { }

    static Path create() throws IOException {
        String external = System.getenv("HEXPROOF_FORGE_PROFILE");
        if (external != null && !external.isBlank()) {
            Path root = Path.of(external).toAbsolutePath().normalize();
            if (!Files.isDirectory(root) || Files.isSymbolicLink(root)) {
                throw new IOException("The supervised Forge profile must be an existing directory");
            }
            System.setProperty("forge.processProfile", root.toString());
            return root; // The supervising process owns creation and cleanup.
        }
        Path root = Files.createTempDirectory("hexproof-forge-").toAbsolutePath();
        System.setProperty("forge.processProfile", root.toString());
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            try {
                // walkFileTree does not follow links. Only this generated root
                // and its descendants can be removed, including on termination.
                Files.walkFileTree(root, new SimpleFileVisitor<>() {
                    @Override public FileVisitResult visitFile(Path path, BasicFileAttributes attributes) throws IOException {
                        Files.deleteIfExists(path);
                        return FileVisitResult.CONTINUE;
                    }
                    @Override public FileVisitResult postVisitDirectory(Path path, IOException error) throws IOException {
                        if (error != null) throw error;
                        Files.deleteIfExists(path);
                        return FileVisitResult.CONTINUE;
                    }
                });
            } catch (IOException error) {
                System.err.println("Native Forge temporary profile cleanup failed: " + error.getClass().getSimpleName());
            }
        }, "Hexproof-Native-Profile-Cleanup"));
        return root;
    }
}
