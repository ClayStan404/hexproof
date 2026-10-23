// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReceiverConfigurationRejectsRetiredAssessment(t *testing.T) {
	public, _ := publicFixture(t)
	dir := t.TempDir()
	public.DataDir = filepath.Join(dir, "public")
	public.TokenFile = filepath.Join(dir, "publisher-token-not-opened")
	config := Config{SchemaVersion: 2, Listen: "127.0.0.1:57324", PublicURL: "https://support.example.invalid/feedback/v2", DataDir: filepath.Join(dir, "legacy"), OperatorName: "Test", MonitoringConfigured: true, Public: &public}
	for _, test := range []struct {
		name       string
		assessment json.RawMessage
	}{
		{name: "absent"},
		{name: "previous bridge", assessment: json.RawMessage(`{"endpoint":"https://controller.example.invalid/autonomy/v1","expectedInstanceId":"32248021-a93a-470f-93d4-f35b4dbdc756","tokenFile":"/does-not-exist/retired-token","pollSeconds":30,"casesPerCycle":8}`)},
		{name: "empty object", assessment: json.RawMessage(`{}`)},
		{name: "null", assessment: json.RawMessage(`null`)},
		{name: "false", assessment: json.RawMessage(`false`)},
	} {
		t.Run(test.name, func(t *testing.T) {
			candidate := config
			candidate.Assessment = test.assessment
			raw, err := json.Marshal(candidate)
			if err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(t.TempDir(), "config.json")
			if err = os.WriteFile(path, raw, 0600); err != nil {
				t.Fatal(err)
			}
			_, err = LoadConfig(path)
			if test.assessment == nil {
				if err != nil {
					t.Fatal("ordinary public receiver configuration was rejected", err)
				}
			} else if err == nil || !strings.Contains(err.Error(), "assessment configuration is retired") {
				t.Fatal("retired assessment configuration did not fail explicitly", err)
			}
		})
	}
	for _, path := range []string{config.DataDir, public.DataDir, public.TokenFile} {
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Fatal("configuration validation created receiver state", path, err)
		}
	}
}

func TestReceiverMulticaConfigurationBoundary(t *testing.T) {
	public, _ := publicFixture(t)
	dir := t.TempDir()
	public.DataDir = filepath.Join(dir, "public")
	public.TokenFile = filepath.Join(dir, "publisher-token")
	public.ProviderPolicyRevision = nativeRuntimePolicy
	native := MulticaConfig{WebhookFile: filepath.Join(dir, "webhook"), Socket: filepath.Join(dir, "legacy", "native.sock"), WorkspaceID: multicaTestWorkspace, AutopilotID: multicaTestAutopilot, ProviderPolicyRevision: nativeRuntimePolicy}
	base := Config{SchemaVersion: 2, PublicURL: public.PublicURL, DataDir: filepath.Join(dir, "legacy"), OperatorName: "Fixture", MonitoringConfigured: true, Public: &public, Multica: &native}
	if err := base.Validate(); err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		name   string
		mutate func(*Config)
	}{
		{"v1", func(c *Config) {
			c.SchemaVersion = 1
			c.PublicURL = "https://support.example.invalid/feedback/v1"
			c.Public = nil
		}},
		{"no consent", func(c *Config) {
			c.Multica.ProviderPolicyRevision = "none-v1"
			c.Public.ProviderPolicyRevision = "none-v1"
		}},
		{"different policy", func(c *Config) { c.Multica.ProviderPolicyRevision = "another-policy" }},
		{"legacy socket", func(c *Config) { c.Multica.Socket = c.AdminSocket }},
		{"public store socket", func(c *Config) { c.Multica.Socket = filepath.Join(c.Public.DataDir, "native.sock") }},
		{"arbitrary legacy entry", func(c *Config) { c.Multica.Socket = filepath.Join(c.DataDir, "other.sock") }},
	} {
		t.Run(test.name, func(t *testing.T) {
			candidate := base
			p, m := *base.Public, *base.Multica
			candidate.Public, candidate.Multica = &p, &m
			test.mutate(&candidate)
			if err := candidate.Validate(); err == nil {
				t.Fatal("invalid native connection accepted")
			}
		})
	}
	if _, err := os.Stat(base.DataDir); !os.IsNotExist(err) {
		t.Fatal("validation created receiver state", err)
	}
}
