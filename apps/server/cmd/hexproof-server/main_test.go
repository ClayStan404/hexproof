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
