// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"context"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net"
	"net/smtp"
	"net/textproto"
	"os"
	"strconv"
	"strings"
	"time"
)

type SMTPSender struct {
	config    SMTPConfig
	password  string
	tlsConfig *tls.Config
}

func NewSMTPSender(config SMTPConfig) (*SMTPSender, error) {
	password, err := smtpPassword(config)
	if err != nil {
		return nil, err
	}
	return &SMTPSender{config: config, password: password}, nil
}

func smtpPassword(config SMTPConfig) (string, error) {
	if config.PasswordFile == "" {
		return "", nil
	}
	info, err := os.Lstat(config.PasswordFile)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0 || info.Size() > 4096 {
		return "", fmt.Errorf("SMTP password must be a bounded private regular file")
	}
	raw, err := os.ReadFile(config.PasswordFile)
	if err != nil {
		return "", fmt.Errorf("SMTP password unavailable")
	}
	value := strings.TrimRight(string(raw), "\r\n")
	if value == "" || strings.ContainsAny(value, "\r\n\x00") {
		return "", fmt.Errorf("invalid SMTP password")
	}
	return value, nil
}

func (s *SMTPSender) Send(ctx context.Context, job MailJob) MailResult {
	if !oneOf(s.config.TLSMode, "tls", "starttls") {
		return MailResult{"needs_attention", "relay_tls_required"}
	}
	message, err := mailMessage(s.config, job)
	if err != nil {
		return MailResult{"needs_attention", "mail_encoding_failed"}
	}
	dialer := &net.Dialer{Timeout: 10 * time.Second}
	conn, err := dialer.DialContext(ctx, "tcp", net.JoinHostPort(s.config.Host, strconv.Itoa(s.config.Port)))
	if err != nil {
		return MailResult{"retry_wait", "relay_unavailable"}
	}
	defer conn.Close()
	transport := conn
	stop := context.AfterFunc(ctx, func() { _ = transport.Close() })
	defer stop()
	_ = conn.SetDeadline(time.Now().Add(30 * time.Second))
	tlsConfig := &tls.Config{ServerName: s.config.Host, MinVersion: tls.VersionTLS12}
	if s.tlsConfig != nil {
		tlsConfig = s.tlsConfig.Clone()
	}
	if s.config.TLSMode == "tls" {
		secured := tls.Client(conn, tlsConfig)
		if err := secured.HandshakeContext(ctx); err != nil {
			return MailResult{"retry_wait", "relay_tls_failed"}
		}
		conn = secured
	}
	client, err := smtp.NewClient(conn, s.config.Host)
	if err != nil {
		return smtpFailure(err, false)
	}
	defer client.Close()
	if s.config.TLSMode == "starttls" {
		if ok, _ := client.Extension("STARTTLS"); !ok {
			return MailResult{"needs_attention", "relay_tls_required"}
		}
		if err := client.StartTLS(tlsConfig); err != nil {
			return MailResult{"retry_wait", "relay_tls_failed"}
		}
	}
	if s.config.Username != "" {
		if err := client.Auth(smtp.PlainAuth("", s.config.Username, s.password, s.config.Host)); err != nil {
			return smtpFailure(err, false)
		}
	}
	if err := client.Mail(s.config.From); err != nil {
		return smtpFailure(err, false)
	}
	if err := client.Rcpt(s.config.To); err != nil {
		return smtpFailure(err, false)
	}
	w, err := client.Data()
	if err != nil {
		return smtpFailure(err, false)
	}
	if _, err = w.Write(message); err != nil {
		return smtpFailure(err, false)
	}
	if err = w.Close(); err != nil {
		return smtpFailure(err, true)
	}
	// A QUIT failure cannot undo an observed successful DATA reply.
	return MailResult{"handed_off", "relay_accepted"}
}

func smtpFailure(err error, possiblyAccepted bool) MailResult {
	var reply *textproto.Error
	if errors.As(err, &reply) {
		if reply.Code >= 500 && reply.Code <= 599 {
			return MailResult{"needs_attention", "relay_rejected"}
		}
		if reply.Code >= 400 && reply.Code <= 499 {
			return MailResult{"retry_wait", "relay_temporary"}
		}
	}
	if possiblyAccepted {
		return MailResult{"uncertain", "relay_outcome_unknown"}
	}
	return MailResult{"retry_wait", "relay_unavailable"}
}

func mailMessage(c SMTPConfig, job MailJob) ([]byte, error) {
	if job.Record.Submission == nil || !validID(job.ID) || !validEmail(c.From) || !validEmail(c.To) {
		return nil, ErrInvalid
	}
	sub := job.Record.Submission
	if !oneOf(sub.Manifest.Category, "problem", "suggestion", "other") {
		return nil, ErrInvalid
	}
	out := &limitedBuffer{limit: 8 << 20}
	mw := multipart.NewWriter(out)
	domain := strings.Split(c.From, "@")[1]
	headers := fmt.Sprintf("From: %s\r\nTo: %s\r\nSubject: Hexproof feedback [%s] %s\r\nMessage-ID: <hexproof-feedback-%s@%s>\r\nDate: %s\r\nMIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=%q\r\n\r\n", c.From, c.To, sub.Manifest.Category, job.ID, job.ID, domain, mustTime(job.Record.Receipt.AcceptedAt).Format(time.RFC1123Z), mw.Boundary())
	if _, err := io.WriteString(out, headers); err != nil {
		return nil, err
	}
	contextJSON, _ := json.Marshal(sub.Manifest.Context)
	body := "Hexproof feedback (user-provided evidence)\r\nReceipt: " + job.ID + "\r\nReceived: " + job.Record.Receipt.AcceptedAt + "\r\nContact (unverified): " + sub.Manifest.ReplyEmail + "\r\n\r\n" + sub.Manifest.Description + "\r\n\r\nTechnical context: " + string(contextJSON) + "\r\n"
	if err := writeMIMEPart(mw, "text/plain; charset=utf-8", "", []byte(body)); err != nil {
		return nil, err
	}
	for _, b := range sub.Blobs {
		extension := ".json"
		if b.Attachment.MediaType == "image/png" {
			extension = ".png"
		} else if b.Attachment.MediaType == "image/jpeg" {
			extension = ".jpg"
		}
		if !attachmentPattern.MatchString(b.Attachment.ID) {
			return nil, ErrInvalid
		}
		name := b.Attachment.Kind + "-" + b.Attachment.ID + extension
		if err := writeMIMEPart(mw, b.Attachment.MediaType, name, b.Bytes); err != nil {
			return nil, err
		}
	}
	if err := mw.Close(); err != nil {
		return nil, err
	}
	return out.Bytes(), nil
}

func writeMIMEPart(mw *multipart.Writer, kind, name string, raw []byte) error {
	header := textproto.MIMEHeader{"Content-Type": {kind}, "Content-Transfer-Encoding": {"base64"}}
	if name != "" {
		header.Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", name))
	}
	w, err := mw.CreatePart(header)
	if err != nil {
		return err
	}
	encoded := base64.StdEncoding.EncodeToString(raw)
	for len(encoded) > 0 {
		n := len(encoded)
		if n > 76 {
			n = 76
		}
		if _, err := io.WriteString(w, encoded[:n]+"\r\n"); err != nil {
			return err
		}
		encoded = encoded[n:]
	}
	return nil
}
