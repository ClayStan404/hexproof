// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/textproto"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

func fakeSMTP(t *testing.T, outcome string) (*SMTPSender, <-chan string) {
	t.Helper()
	certServer := httptest.NewTLSServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	cert := certServer.TLS.Certificates[0]
	root := x509.NewCertPool()
	root.AddCert(certServer.Certificate())
	certServer.Close()
	listener, err := tls.Listen("tcp", "127.0.0.1:0", &tls.Config{Certificates: []tls.Certificate{cert}, MinVersion: tls.VersionTLS12})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { listener.Close() })
	messages := make(chan string, 1)
	go func() {
		defer close(messages)
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
		p := textproto.NewConn(conn)
		defer p.Close()
		_ = p.PrintfLine("220 test receiver")
		for {
			line, err := p.ReadLine()
			if err != nil {
				return
			}
			switch {
			case strings.HasPrefix(line, "EHLO"):
				_ = p.PrintfLine("250-test receiver")
				_ = p.PrintfLine("250 8BITMIME")
			case strings.HasPrefix(line, "MAIL FROM"), strings.HasPrefix(line, "RCPT TO"):
				_ = p.PrintfLine("250 accepted")
			case line == "DATA":
				_ = p.PrintfLine("354 data")
				raw, err := p.ReadDotBytes()
				if err != nil {
					return
				}
				messages <- string(raw)
				switch outcome {
				case "drop":
					return
				case "temporary":
					_ = p.PrintfLine("451 temporary failure")
				case "permanent":
					_ = p.PrintfLine("550 rejected")
				default:
					_ = p.PrintfLine("250 stored")
				}
			case line == "QUIT":
				_ = p.PrintfLine("221 bye")
				return
			default:
				_ = p.PrintfLine("500 unexpected")
			}
		}
	}()
	host, portText, _ := net.SplitHostPort(listener.Addr().String())
	port, _ := strconv.Atoi(portText)
	sender, err := NewSMTPSender(SMTPConfig{Host: host, Port: port, TLSMode: "tls", From: "feedback@example.invalid", To: "support@example.invalid"})
	if err != nil {
		t.Fatal(err)
	}
	sender.tlsConfig = &tls.Config{RootCAs: root, ServerName: host, MinVersion: tls.VersionTLS12}
	return sender, messages
}

func TestSMTPFinalAcceptanceOutcomesAndPrivateMIME(t *testing.T) {
	for _, test := range []struct{ outcome, state string }{{"accept", "handed_off"}, {"drop", "uncertain"}, {"temporary", "retry_wait"}, {"permanent", "needs_attention"}} {
		t.Run(test.outcome, func(t *testing.T) {
			s, _ := testStore(t)
			acceptTest(t, s)
			job, err := s.Claim(context.Background())
			if err != nil || job == nil {
				t.Fatal(err)
			}
			sender, messages := fakeSMTP(t, test.outcome)
			result := sender.Send(context.Background(), *job)
			if result.State != test.state {
				t.Fatal(result)
			}
			message := <-messages
			if !strings.Contains(message, "Message-ID: <hexproof-feedback-"+testID+"@example.invalid>") || strings.Contains(message, "Authorization") || strings.Contains(message, "SecretHash") || strings.Contains(message, string(testSecret)) {
				t.Fatal("unsafe or missing MIME headers")
			}
			if strings.Contains(message, "Reply-To:") {
				t.Fatal("unverified user contact became a header")
			}
			if err := s.Finish(context.Background(), *job, result); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestSMTPUnknownBeforeDataIsRetryableAndTLSRequired(t *testing.T) {
	s, _ := testStore(t)
	acceptTest(t, s)
	job, err := s.Claim(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	go func() {
		c, err := listener.Accept()
		if err == nil {
			c.Close()
		}
	}()
	host, portText, _ := net.SplitHostPort(listener.Addr().String())
	port, _ := strconv.Atoi(portText)
	sender, _ := NewSMTPSender(SMTPConfig{Host: host, Port: port, TLSMode: "tls", From: "f@example.invalid", To: "s@example.invalid"})
	if result := sender.Send(context.Background(), *job); result.State != "retry_wait" {
		t.Fatal(result)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if result := sender.Send(ctx, *job); result.State != "retry_wait" {
		t.Fatal(result)
	}
}

func TestConfigurationPreflightAndAdminSocket(t *testing.T) {
	dir := t.TempDir()
	c := Config{SchemaVersion: 1, Listen: "127.0.0.1:57324", PublicURL: "https://support.example.invalid/feedback/v1", DataDir: filepath.Join(dir, "not-created"), OperatorName: "test operator", MonitoringConfigured: true, SMTP: SMTPConfig{Host: "localhost", Port: 465, TLSMode: "tls", From: "f@example.invalid", To: "s@example.invalid"}}
	if err := c.Validate(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(c.DataDir); !os.IsNotExist(err) {
		t.Fatal("preflight opened store")
	}
	c.SMTP.TLSMode = "plain"
	if c.Validate() == nil {
		t.Fatal("plaintext SMTP accepted")
	}
	c.SMTP.TLSMode = "tls"
	c.PublicURL = "https://support.example.invalid/feedback/v1?token=secret"
	if c.Validate() == nil {
		t.Fatal("query endpoint accepted")
	}
	password := filepath.Join(dir, "password")
	if err := os.WriteFile(password, []byte("test-password"), 0644); err != nil {
		t.Fatal(err)
	}
	if _, err := NewSMTPSender(SMTPConfig{PasswordFile: password}); err == nil {
		t.Fatal("public password file accepted")
	}
	if err := os.Chmod(password, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := NewSMTPSender(SMTPConfig{PasswordFile: password}); err != nil {
		t.Fatal(err)
	}
	s, _ := testStore(t)
	acceptTest(t, s)
	socket := filepath.Join(s.dir, "admin.sock")
	server, listener, err := StartAdmin(socket, s)
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	go server.Serve(listener)
	info, err := os.Stat(socket)
	if err != nil || info.Mode().Perm() != 0600 {
		t.Fatal("admin permissions", err)
	}
	transport := &http.Transport{DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "unix", socket)
	}}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: time.Second}
	response, err := client.Post("http://localhost/admin", "application/json", strings.NewReader(`{"action":"discard","receipt":"`+testID+`"}`))
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, _ := io.ReadAll(response.Body)
	if response.StatusCode != 200 {
		t.Fatal(response.StatusCode, string(body))
	}
	if job, err := s.Claim(context.Background()); err != nil || job != nil {
		t.Fatal("discarded item deliverable")
	}
}
