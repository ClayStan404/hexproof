// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package accounts

import (
	"context"
	"errors"
	"testing"

	"hexproof/server/internal/benchutil"
)

func BenchmarkControlPlaneAccountStore(b *testing.B) {
	for _, scenario := range []string{"Independent", "SameAccount"} {
		b.Run(scenario, func(b *testing.B) {
			s, err := Open(b.TempDir())
			if err != nil {
				b.Fatal(err)
			}
			b.Cleanup(func() { s.Close() })
			ctx := context.Background()
			identities := make([]Result, benchutil.Workers+1)
			for i := range identities {
				out, err := s.Do(ctx, Request{Operation: "create", Name: "Benchmark", DeviceName: "Desktop"})
				if err != nil {
					b.Fatal(err)
				}
				// Use a full device inventory to include credential validation cost.
				for device := 1; device < MaxSessions; device++ {
					login, err := s.Do(ctx, Request{Operation: "login", LoginCode: out.LoginCode, DeviceName: "Desktop"})
					if err != nil {
						b.Fatal(err)
					}
					out.SessionToken = login.SessionToken
				}
				identities[i] = out
			}
			var stall benchutil.Stall
			s.saveRecord = func(r record) error {
				if err := stall.Wait(ctx); err != nil {
					return err
				}
				// Retain the real marshal/write/fsync/rename after the injected delay.
				return s.save(r)
			}
			benchutil.Run(b, &stall, func(ctx context.Context) error {
				out, err := s.Do(ctx, Request{Operation: "rename", SessionToken: identities[0].SessionToken, Name: "Renamed"})
				if err == nil && out.Profile.Name != "Renamed" {
					return errors.New("write returned the wrong profile")
				}
				return err
			}, func(ctx context.Context, worker int) error {
				identity := identities[worker+1]
				if scenario == "SameAccount" {
					identity = identities[0]
				}
				out, err := s.Do(ctx, Request{Operation: "check", SessionToken: identity.SessionToken})
				if err == nil && (out.Profile.ID != identity.Profile.ID || out.SessionID == "") {
					return errors.New("check returned the wrong identity")
				}
				return err
			})
		})
	}
}
