// SPDX-License-Identifier: GPL-2.0-only
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package server

import "time"

// Config contains bounded public-hub operational settings. Zero values are
// normalized to conservative defaults by NewHandlerWithConfig.
type Config struct {
	ReconnectWindow             time.Duration
	HelloTimeout                time.Duration
	RetentionTTL                time.Duration
	RetentionDir                string
	RetentionMaxFiles           int
	RetentionMaxBytes           int64
	ReplayPageSize              int
	TrustedProxyCIDRs           []string
	MaxRooms                    int
	MaxTournaments              int
	MaxConnections              int64
	MaxMessageBytes             int64
	MessagesPerSecond           int
	ReplayRequestsPerMinute     int
	RoomCreatesPerMinute        int
	TournamentCreatesPerMinute  int
	TournamentClosedTTL         time.Duration
	TournamentInactiveTTL       time.Duration
	TournamentAbandonedTTL      time.Duration
	PasswordJoinsPerMinute      int
	MaxConcurrentPasswordChecks int
}

// DefaultConfig returns limits suitable for a small public home hub. Retention
// storage is disabled here so tests and embedders do not write implicitly;
// the server command enables its configured retention directory by default.
func DefaultConfig() Config {
	return Config{
		ReconnectWindow:             3 * time.Minute,
		HelloTimeout:                10 * time.Second,
		RetentionTTL:                7 * 24 * time.Hour,
		RetentionMaxFiles:           512,
		RetentionMaxBytes:           512 << 20,
		ReplayPageSize:              50,
		TrustedProxyCIDRs:           []string{"127.0.0.1/32", "::1/128"},
		MaxRooms:                    256,
		MaxTournaments:              64,
		MaxConnections:              1024,
		MaxMessageBytes:             1 << 20,
		MessagesPerSecond:           60,
		ReplayRequestsPerMinute:     30,
		RoomCreatesPerMinute:        6,
		TournamentCreatesPerMinute:  3,
		TournamentClosedTTL:         24 * time.Hour,
		TournamentInactiveTTL:       2 * time.Hour,
		TournamentAbandonedTTL:      24 * time.Hour,
		PasswordJoinsPerMinute:      20,
		MaxConcurrentPasswordChecks: 8,
	}
}

func normalizeConfig(config Config) Config {
	defaults := DefaultConfig()
	if config.ReconnectWindow <= 0 {
		config.ReconnectWindow = defaults.ReconnectWindow
	}
	if config.HelloTimeout <= 0 {
		config.HelloTimeout = defaults.HelloTimeout
	}
	if config.RetentionTTL <= 0 {
		config.RetentionTTL = defaults.RetentionTTL
	}
	if config.RetentionMaxFiles <= 0 {
		config.RetentionMaxFiles = defaults.RetentionMaxFiles
	}
	if config.RetentionMaxBytes <= 0 {
		config.RetentionMaxBytes = defaults.RetentionMaxBytes
	}
	if config.ReplayPageSize <= 0 {
		config.ReplayPageSize = defaults.ReplayPageSize
	}
	if config.TrustedProxyCIDRs == nil {
		config.TrustedProxyCIDRs = defaults.TrustedProxyCIDRs
	}
	if config.MaxRooms <= 0 {
		config.MaxRooms = defaults.MaxRooms
	}
	if config.MaxTournaments <= 0 {
		config.MaxTournaments = defaults.MaxTournaments
	}
	if config.MaxConnections <= 0 {
		config.MaxConnections = defaults.MaxConnections
	}
	if config.MaxMessageBytes <= 0 {
		config.MaxMessageBytes = defaults.MaxMessageBytes
	}
	if config.MessagesPerSecond <= 0 {
		config.MessagesPerSecond = defaults.MessagesPerSecond
	}
	if config.ReplayRequestsPerMinute <= 0 {
		config.ReplayRequestsPerMinute = defaults.ReplayRequestsPerMinute
	}
	if config.RoomCreatesPerMinute <= 0 {
		config.RoomCreatesPerMinute = defaults.RoomCreatesPerMinute
	}
	if config.TournamentCreatesPerMinute <= 0 {
		config.TournamentCreatesPerMinute = defaults.TournamentCreatesPerMinute
	}
	if config.TournamentClosedTTL <= 0 {
		config.TournamentClosedTTL = defaults.TournamentClosedTTL
	}
	if config.TournamentInactiveTTL <= 0 {
		config.TournamentInactiveTTL = defaults.TournamentInactiveTTL
	}
	if config.TournamentAbandonedTTL <= 0 {
		config.TournamentAbandonedTTL = defaults.TournamentAbandonedTTL
	}
	if config.PasswordJoinsPerMinute <= 0 {
		config.PasswordJoinsPerMinute = defaults.PasswordJoinsPerMinute
	}
	if config.MaxConcurrentPasswordChecks <= 0 {
		config.MaxConcurrentPasswordChecks = defaults.MaxConcurrentPasswordChecks
	}
	return config
}
