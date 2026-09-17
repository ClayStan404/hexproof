// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors
package org.hexproof.forge;

import forge.gui.interfaces.IGuiBase;
import forge.util.ThreadUtil;
import java.lang.reflect.*;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.*;

/** Headless native GUI dispatcher. Unsupported decisions never receive defaults. */
final class NativeGuiBase implements InvocationHandler, AutoCloseable {
    private final ExecutorService edt = Executors.newSingleThreadExecutor(r -> new Thread(r, "Hexproof-Bootstrap-EDT"));
    private final String assets;
    private NativeExecution testContext;
    private final IGuiBase proxy;
    private static final Set<String> PRESENTATION = Set.of("copyToClipboard", "browseToUrl", "clearImageCache", "preventSystemSleep", "startAltSoundSystem");
    NativeGuiBase(String assets) {
        this.assets = Path.of(assets).toAbsolutePath() + "/";
        proxy = (IGuiBase) Proxy.newProxyInstance(IGuiBase.class.getClassLoader(), new Class<?>[]{IGuiBase.class}, this);
    }
    IGuiBase proxy() { return proxy; }
    // Mechanism tests call native controls directly outside a game task. The
    // production host never configures a fallback game or global failure owner.
    void setTestSession(NativeSession session) { testContext = session.context; }
    private NativeExecution context() {
        var current = ThreadUtil.executionContext();
        return current instanceof NativeExecution value ? value : testContext;
    }
    boolean isEdt() {
        var owner = context();
        return owner != null ? owner.isEdt() : Thread.currentThread().getName().equals("Hexproof-Bootstrap-EDT");
    }
    void later(Runnable action) {
        var owner = context();
        if (owner != null) owner.later(action);
        else edt.execute(action);
    }
    void andWait(Runnable action) throws Exception {
        var owner = context();
        if (owner != null) owner.andWait(action);
        else if (isEdt()) action.run();
        else edt.submit(action).get(30, TimeUnit.SECONDS);
    }
    @Override public Object invoke(Object p, Method m, Object[] args) throws Throwable {
        if (m.isDefault()) return InvocationHandler.invokeDefault(p, m, args);
        return switch (m.getName()) {
            case "toString" -> "HexproofNativeGuiBase";
            case "getAssetsDir" -> assets;
            case "getCurrentVersion" -> "hexproof-native-" + NativeHost.FORGE_COMMIT;
            case "isRunningOnDesktop" -> true;
            case "isLibgdxPort", "hasNetGame", "isSupportedAudioFormat" -> false;
            case "isGuiThread" -> isEdt();
            case "invokeInEdtNow", "invokeInEdtAndWait" -> { andWait((Runnable) args[0]); yield null; }
            case "invokeInEdtLater" -> { later((Runnable) args[0]); yield null; }
            case "getImageFetcher", "getSkinIcon", "getUnskinnedIcon", "getCardArt", "createLayeredImage", "createAudioClip", "createAudioMusic" -> null;
            case "getAvatarCount", "getSleevesCount" -> 0;
            case "getScreenScale" -> 1.0f;
            case "encodeSymbols" -> args[0];
            case "runBackgroundTask" -> { ((Runnable) args[1]).run(); yield null; }
            default -> {
                if (PRESENTATION.contains(m.getName())) yield null;
                throw new UnsupportedOperationException("Unhandled IGuiBase callback: " + m.getName());
            }
        };
    }
    @Override public void close() { edt.shutdownNow(); }
}
