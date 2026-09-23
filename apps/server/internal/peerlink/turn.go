// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package peerlink

import (
	"fmt"
	"strings"

	"github.com/pion/stun/v4"
)

// TURNServer holds short-lived credentials delivered by the authenticated
// operator gateway. Never include these values in transport diagnostics.
type TURNServer struct {
	URLs       []string `json:"urls"`
	Username   string   `json:"username"`
	Credential string   `json:"credential"`
}

func ValidateTURNServers(servers []TURNServer) error {
	if len(servers) > 2 {
		return fmt.Errorf("at most two TURN servers are supported")
	}
	for _, server := range servers {
		if len(server.URLs) == 0 || len(server.URLs) > 3 || len(server.Username) == 0 || len(server.Username) > 256 || len(server.Credential) == 0 || len(server.Credential) > 256 || strings.ContainsAny(server.Username+server.Credential, "\r\n\x00") {
			return fmt.Errorf("invalid TURN credentials or endpoint count")
		}
		for _, endpoint := range server.URLs {
			if len(endpoint) > 256 || strings.ContainsAny(endpoint, "@/#\\ \r\n\t") {
				return fmt.Errorf("invalid TURN endpoint")
			}
			uri, err := stun.ParseURI(endpoint)
			if err != nil || (uri.Scheme != stun.SchemeTypeTURN && uri.Scheme != stun.SchemeTypeTURNS) || uri.Port < 1 || uri.Port > 65535 || (uri.Scheme == stun.SchemeTypeTURNS && uri.Proto != stun.ProtoTypeTCP) {
				return fmt.Errorf("invalid TURN server scheme, host, port or transport")
			}
		}
	}
	return nil
}
