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
	return &legacyCompatibility{store: store, sender: sender}, nil
}

func (l *legacyCompatibility) run(ctx context.Context) {
	if l.sender != nil {
		feedback.RunOutbox(ctx, l.store, l.sender)
	} else {
		feedback.RunRetention(ctx, l.store)
	}
}
