// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package main

import (
	"context"
	"fmt"
	"time"

	"hexproof/server/internal/feedback"
)

// legacyCompatibility owns private V1 retention and any unfinished mail. Public
// conversations use a separate store; this path never exports private records.
// The directory also retains its established admin/native socket locations.
type legacyCompatibility struct {
	store  *feedback.Store
	sender feedback.MailSender
	close  func() error
}

func openLegacyCompatibility(c feedback.Config, sender feedback.MailSender) (*legacyCompatibility, error) {
	store, err := feedback.OpenStore(c.DataDir, c.Limits)
	if err != nil {
		return nil, fmt.Errorf("legacy feedback store could not be opened")
	}
	if c.Public != nil && sender == nil {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		needsSMTP, err := feedback.PrepareLegacyStore(ctx, store)
		cancel()
		if err != nil || needsSMTP {
			store.Close()
			if err != nil {
				return nil, fmt.Errorf("legacy feedback retention could not be verified")
			}
			return nil, fmt.Errorf("unfinished private deliveries require legacy SMTP configuration")
		}
	}
	legacy := &legacyCompatibility{close: store.Close}
	if c.Public == nil || len(store.IDs()) != 0 {
		legacy.store, legacy.sender = store, sender
	}
	// Empty public deployments retain only the directory lease. This prevents an
	// old V1 process writing there while V2 has no legacy handlers or workers.
	return legacy, nil
}

func (l *legacyCompatibility) Close() error {
	return l.close()
}

func (l *legacyCompatibility) run(ctx context.Context) {
	if l.store == nil {
		return
	}
	if l.sender != nil {
		feedback.RunOutbox(ctx, l.store, l.sender)
	} else {
		feedback.RunRetention(ctx, l.store)
	}
}
