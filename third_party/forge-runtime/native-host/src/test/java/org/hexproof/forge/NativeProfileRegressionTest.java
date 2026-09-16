// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import forge.gui.GuiBase;
import forge.localinstance.properties.ForgeConstants;
import forge.localinstance.properties.ForgeProfileProperties;
import java.nio.file.*;

/** Run in a fresh JVM: constants must select private paths before model startup. */
public final class NativeProfileRegressionTest {
    public static void main(String[] args) throws Exception {
        Path profile = NativeProfile.create();
        Path assets = profile.resolve("test-assets");
        Files.createDirectories(assets);
        Path shared = assets.resolve("forge.profile.properties");
        String sentinel = "userDir=" + assets.resolve("forbidden-data") + "\ncacheDir="
                + assets.resolve("forbidden-cache") + "\n";
        Files.writeString(shared, sentinel);
        try (NativeGuiBase base = new NativeGuiBase(assets.toString())) {
            GuiBase.setInterface(base.proxy());
            require(Path.of(ForgeConstants.USER_DIR).normalize().equals(profile.resolve("data")), "shared profile overrode private user path");
            require(Path.of(ForgeProfileProperties.getCacheDir()).normalize().equals(profile.resolve("cache")), "cache escaped profile");
            require(Path.of(ForgeProfileProperties.getCardPicsDir()).normalize().startsWith(profile), "card images escaped profile");
            require(Path.of(ForgeProfileProperties.getDecksDir()).normalize().startsWith(profile), "decks escaped profile");
            require(!Files.exists(assets.resolve("forbidden-data")), "shared user directory was created");
            require(!Files.exists(assets.resolve("forbidden-cache")), "shared cache directory was created");
            ForgeProfileProperties.setUserDir(ForgeConstants.USER_DIR);
            require(Files.readString(shared).equals(sentinel), "profile setter wrote shared assets");
        }
        System.out.println("PASS native process profile isolation: " + profile);
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
