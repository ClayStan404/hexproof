// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package main

import (
	"io"
	"reflect"
	"testing"
)

func TestHostedForgeRuntimeDiscardsPrivateDiagnostics(t *testing.T) {
	configured := hostedForgeRuntimeConfig("java", "/runtime/forge-harness.jar", "/runtime/forge-gui")
	if configured.Stderr != io.Discard {
		t.Fatal("hosted Forge must not forward raw engine diagnostics")
	}
	if configured.Command != "java" || !reflect.DeepEqual(configured.Args, []string{
		"-jar", "/runtime/forge-harness.jar", "--interactive-server", "--forge-home", "/runtime/forge-gui",
	}) {
		t.Fatalf("hosted runtime configuration = %+v", configured)
	}
}

func TestForgeRuntimeDefaults(t *testing.T) {
	t.Setenv("HEXPROOF_FORGE_HARNESS", "/srv/forge/forge-harness.jar")
	t.Setenv("HEXPROOF_FORGE_HOME", "/srv/forge/forge-gui")
	t.Setenv("HEXPROOF_FORGE_JAVA", "/usr/lib/jvm/java-21/bin/java")

	harness, home, javaCommand := forgeRuntimeDefaults()
	if harness != "/srv/forge/forge-harness.jar" || home != "/srv/forge/forge-gui" ||
		javaCommand != "/usr/lib/jvm/java-21/bin/java" {
		t.Fatalf("Forge defaults = %q, %q, %q", harness, home, javaCommand)
	}
}

func TestForgeRuntimeDefaultsUseJavaFromPath(t *testing.T) {
	t.Setenv("HEXPROOF_FORGE_HARNESS", "")
	t.Setenv("HEXPROOF_FORGE_HOME", "")
	t.Setenv("HEXPROOF_FORGE_JAVA", "")

	harness, home, javaCommand := forgeRuntimeDefaults()
	if harness != "" || home != "" || javaCommand != "java" {
		t.Fatalf("Forge defaults = %q, %q, %q", harness, home, javaCommand)
	}
}

func TestForgeGameLimit(t *testing.T) {
	for _, value := range []string{"", "0", "-1", "unlimited", "1.5", "99999999999999999999999999"} {
		if _, err := parseForgeGameLimit(value); err == nil {
			t.Errorf("accepted invalid Forge process limit %q", value)
		}
	}
	for _, value := range []string{"1", " 2 ", "16"} {
		if limit, err := parseForgeGameLimit(value); err != nil || limit < 1 {
			t.Errorf("rejected Forge process limit %q: %d, %v", value, limit, err)
		}
	}
	t.Setenv("HEXPROOF_FORGE_MAX_GAMES", "2")
	if value := forgeMaxGamesDefault(); value != "2" {
		t.Fatalf("Forge capacity environment default = %q", value)
	}
	t.Setenv("HEXPROOF_FORGE_MAX_GAMES", "")
	if _, err := parseForgeGameLimit(forgeMaxGamesDefault()); err == nil {
		t.Fatal("explicit empty capacity environment silently used a default")
	}
}
