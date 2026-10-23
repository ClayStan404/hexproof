// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"encoding/json"
	"fmt"
	"net"
	"net/mail"
	"net/netip"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

type Config struct {
	SchemaVersion        int            `json:"schemaVersion"`
	Listen               string         `json:"listen"`
	PublicURL            string         `json:"publicUrl"`
	DataDir              string         `json:"dataDir"`
	AdminSocket          string         `json:"adminSocket,omitempty"`
	OperatorName         string         `json:"operatorName"`
	MonitoringConfigured bool           `json:"monitoringConfigured"`
	TrustedProxyCIDRs    []string       `json:"trustedProxyCidrs,omitempty"`
	Public               *PublicConfig  `json:"public,omitempty"`
	Multica              *MulticaConfig `json:"multica,omitempty"`
	// Assessment only recognizes retired configuration so startup fails clearly.
	Assessment json.RawMessage `json:"assessment,omitempty"`
	SMTP       SMTPConfig      `json:"smtp"`
	Limits     Limits          `json:"limits,omitempty"`
}

type SMTPConfig struct {
	Host         string `json:"host"`
	Port         int    `json:"port"`
	TLSMode      string `json:"tlsMode"`
	Username     string `json:"username,omitempty"`
	PasswordFile string `json:"passwordFile,omitempty"`
	From         string `json:"from"`
	To           string `json:"to"`
}

type Limits struct {
	MaxRecords           int   `json:"maxRecords,omitempty"`
	MaxIdentities        int   `json:"maxIdentities,omitempty"`
	MaxBytes             int64 `json:"maxBytes,omitempty"`
	MinFreeBytes         int64 `json:"minFreeBytes,omitempty"`
	PerSourceSubmissions int   `json:"perSourceSubmissions,omitempty"`
	GlobalSubmissions    int   `json:"globalSubmissions,omitempty"`
	PerSourceBytes       int64 `json:"perSourceBytes,omitempty"`
	GlobalBytes          int64 `json:"globalBytes,omitempty"`
}

func (l Limits) defaults() Limits {
	if l.MaxRecords == 0 {
		l.MaxRecords = 1000
	}
	if l.MaxIdentities == 0 {
		l.MaxIdentities = 10000
	}
	if l.MaxBytes == 0 {
		l.MaxBytes = 2 << 30
	}
	if l.MinFreeBytes == 0 {
		l.MinFreeBytes = 512 << 20
	}
	if l.PerSourceSubmissions == 0 {
		l.PerSourceSubmissions = 5
	}
	if l.GlobalSubmissions == 0 {
		l.GlobalSubmissions = 100
	}
	if l.PerSourceBytes == 0 {
		l.PerSourceBytes = 20 << 20
	}
	if l.GlobalBytes == 0 {
		l.GlobalBytes = 256 << 20
	}
	return l
}

func LoadConfig(path string) (Config, error) {
	var c Config
	f, err := os.Open(path)
	if err != nil {
		return c, fmt.Errorf("configuration unavailable")
	}
	defer f.Close()
	raw, err := readBounded(f, 32<<10)
	if err != nil || decodeClosed(raw, &c) != nil {
		return c, fmt.Errorf("invalid configuration JSON")
	}
	err = c.Validate()
	return c, err
}

func (c *Config) Validate() error {
	if len(c.Assessment) != 0 {
		return fmt.Errorf("assessment configuration is retired; remove assessment and use the external AI platform")
	}
	if (c.SchemaVersion != 1 && c.SchemaVersion != 2) || !filepath.IsAbs(c.DataDir) || strings.TrimSpace(c.OperatorName) == "" || len(c.OperatorName) > 128 || !c.MonitoringConfigured {
		return fmt.Errorf("missing receiver or operator configuration")
	}
	if c.Listen == "" {
		c.Listen = "127.0.0.1:57324"
	}
	host, port, err := net.SplitHostPort(c.Listen)
	ip, ipErr := netip.ParseAddr(host)
	portNumber, portErr := strconv.Atoi(port)
	if err != nil || ipErr != nil || !ip.IsLoopback() || portErr != nil || portNumber < 1 || portNumber > 65535 {
		return fmt.Errorf("receiver must bind a literal loopback address behind its HTTPS proxy")
	}
	u, err := url.Parse(c.PublicURL)
	if err != nil || u.Scheme != "https" || u.Hostname() == "" || u.User != nil || u.RawQuery != "" || u.ForceQuery || u.Fragment != "" || u.Path != map[int]string{1: "/feedback/v1", 2: "/feedback/v2"}[c.SchemaVersion] || u.RawPath != "" {
		return fmt.Errorf("publicUrl must be an HTTPS URL for the configured feedback version")
	}
	if c.AdminSocket == "" {
		c.AdminSocket = filepath.Join(c.DataDir, "admin.sock")
	}
	if filepath.Clean(c.AdminSocket) != filepath.Join(filepath.Clean(c.DataDir), "admin.sock") || len(c.AdminSocket) > 100 {
		return fmt.Errorf("admin socket must be inside the private data directory")
	}
	if len(c.TrustedProxyCIDRs) > 16 {
		return fmt.Errorf("too many trusted proxies")
	}
	for _, cidr := range c.TrustedProxyCIDRs {
		if _, err := netip.ParsePrefix(cidr); err != nil {
			return fmt.Errorf("invalid trusted proxy network")
		}
	}
	if c.SchemaVersion == 2 {
		if c.Public != nil {
			c.Public.PublicURL = c.PublicURL
		}
		if c.Public == nil || c.Public.Validate(c.DataDir) != nil {
			return fmt.Errorf("invalid public feedback configuration")
		}
	} else if c.Public != nil {
		return fmt.Errorf("public configuration requires schemaVersion 2")
	}
	if c.Multica != nil {
		if c.SchemaVersion != 2 || c.Public == nil || c.Multica.Validate() != nil || c.Multica.ProviderPolicyRevision != c.Public.ProviderPolicyRevision || filepath.Clean(c.Multica.Socket) == filepath.Clean(c.AdminSocket) {
			return fmt.Errorf("invalid Multica public feedback configuration")
		}
		// Keep sockets outside the public store's closed record namespace.
		if filepath.Clean(c.Multica.Socket) != filepath.Join(filepath.Clean(c.DataDir), "native.sock") {
			return fmt.Errorf("Multica socket must be native.sock inside the private legacy data directory")
		}
	}
	s := c.SMTP
	if c.SchemaVersion == 1 || s != (SMTPConfig{}) {
		if s.Host == "" || len(s.Host) > 253 || strings.ContainsAny(s.Host, "\r\n\x00 /@") || s.Port < 1 || s.Port > 65535 || (s.TLSMode != "starttls" && s.TLSMode != "tls") || !validEmail(s.From) || !validEmail(s.To) || len(s.Username) > 254 || strings.ContainsAny(s.Username, "\r\n\x00") {
			return fmt.Errorf("invalid SMTP configuration")
		}
		if (s.Username == "") != (s.PasswordFile == "") || (s.PasswordFile != "" && !filepath.IsAbs(s.PasswordFile)) {
			return fmt.Errorf("SMTP credentials require an absolute private password file")
		}
	}
	c.Limits = c.Limits.defaults()
	l := c.Limits
	if l.MaxRecords < 1 || l.MaxRecords > 10000 || l.MaxIdentities < l.MaxRecords || l.MaxIdentities > 100000 || l.MaxBytes < 32<<20 || l.MaxBytes > 1<<40 || l.MinFreeBytes < 16<<20 || l.MinFreeBytes > 1<<40 || l.PerSourceSubmissions < 1 || l.PerSourceSubmissions > 1000 || l.GlobalSubmissions < 1 || l.GlobalSubmissions > 10000 || l.PerSourceBytes < MaxUpload || l.GlobalBytes < MaxUpload || l.PerSourceBytes > 1<<40 || l.GlobalBytes > 1<<40 {
		return fmt.Errorf("invalid receiver limits")
	}
	return nil
}

func validEmail(value string) bool {
	if value == "" || len(value) > 254 || strings.ContainsAny(value, "\r\n\x00") {
		return false
	}
	a, err := mail.ParseAddress(value)
	return err == nil && a.Address == value && a.Name == "" && strings.Count(value, "@") == 1
}
