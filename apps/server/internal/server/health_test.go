// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import (
	"encoding/json"
	"net/http/httptest"
	"reflect"
	"testing"
	"time"

	"hexproof/server/internal/rulesengine/forge"
)

func TestHealthCapabilitiesSeparateHostingFromLocalForge(t *testing.T) {
	for _, test := range []struct {
		name            string
		local, hosting  bool
		closed, cooling bool
	}{
		{name: "manual"},
		{name: "relay without Java", hosting: true},
		{name: "local only", local: true},
		{name: "both", local: true, hosting: true},
		{name: "local retry cooldown", local: true, hosting: true, cooling: true},
		{name: "closed local engine", local: true, closed: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			h := &Handler{config: Config{AllowPlayerHosting: test.hosting}, forgeClosed: test.closed}
			if test.local {
				h.forgeRuntime = &forge.ProcessConfig{}
			}
			if test.cooling {
				h.forgeRetryAfter = time.Now().Add(time.Minute)
			}
			response := httptest.NewRecorder()
			h.ServeHealth(response, httptest.NewRequest("GET", "/healthz", nil))
			if response.Code != 200 || response.Body.String() != "ok\n" || response.Header().Get("Cache-Control") != "no-store" {
				t.Fatalf("incompatible health response: %v %q", response.Code, response.Body.String())
			}
			var capabilities map[string]bool
			if err := json.Unmarshal([]byte(response.Header().Get("X-Hexproof-Capabilities")), &capabilities); err != nil {
				t.Fatal(err)
			}
			want := map[string]bool{"forge": test.local && !test.closed && !test.cooling,
				"playerHosting": test.hosting, "directPeer": test.hosting, "hostMigration": test.hosting}
			if !reflect.DeepEqual(capabilities, want) {
				t.Fatalf("public capabilities = %v; want %v", capabilities, want)
			}
		})
	}
}
