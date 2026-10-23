// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"context"
	"log"
	"math/rand/v2"
	"path/filepath"
	"time"
)

type MailJob struct {
	ID      string
	Record  Record
	Attempt int
}
type MailResult struct {
	State string
	Code  string
}
type MailSender interface {
	Send(context.Context, MailJob) MailResult
}

func (s *Store) Claim(ctx context.Context) (*MailJob, error) {
	if !s.begin() {
		return nil, ErrUnavailable
	}
	defer s.ops.Done()
	for _, id := range s.IDs() {
		e := s.get(id)
		if e == nil {
			continue
		}
		if err := acquire(ctx, e); err != nil {
			return nil, err
		}
		if e.live || e.record.Tombstone || !s.now().Before(mustTime(e.record.Receipt.ContentExpiresAt)) || !oneOf(e.delivery.State, "pending", "retry_wait") {
			release(e)
			continue
		}
		if err := s.readyLocked(e, id); err != nil {
			release(e)
			return nil, err
		}
		if e.record.Tombstone {
			release(e)
			continue
		}
		// Retry eligibility expires before claiming a network attempt, including
		// when a persisted backoff would otherwise wake after the deadline. An
		// explicit operator retry changes the state to pending and remains allowed.
		if e.delivery.State == "retry_wait" && s.now().Sub(mustTime(e.record.Receipt.AcceptedAt)) >= 7*24*time.Hour {
			d := e.delivery
			d.State = "needs_attention"
			d.Code = "retry_exhausted"
			d.UpdatedAt = s.now()
			d.NextAttempt = time.Time{}
			if err := s.saveDeliveryLocked(id, e, d); err != nil {
				release(e)
				return nil, ErrUnavailable
			}
			e.delivery = d
			release(e)
			continue
		}
		if s.now().Before(e.delivery.NextAttempt) {
			release(e)
			continue
		}
		r, _, err := readRecord(filepath.Join(s.dir, id, "record.json"))
		if err != nil {
			release(e)
			return nil, ErrUnavailable
		}
		d := e.delivery
		d.State = "transmitting"
		d.Attempts++
		d.UpdatedAt = s.now()
		d.Code = ""
		d.NextAttempt = time.Time{}
		if s.check("delivery_start") != nil {
			release(e)
			return nil, ErrUnavailable
		}
		if err := s.saveDeliveryLocked(id, e, d); err != nil {
			release(e)
			return nil, ErrUnavailable
		}
		e.delivery = d
		e.live = true
		release(e)
		return &MailJob{ID: id, Record: r, Attempt: d.Attempts}, nil
	}
	return nil, nil
}

func (s *Store) Finish(ctx context.Context, job MailJob, result MailResult) error {
	if !s.begin() {
		return ErrUnavailable
	}
	defer s.ops.Done()
	e := s.get(job.ID)
	if e == nil {
		return ErrNotFound
	}
	if err := acquire(ctx, e); err != nil {
		return err
	}
	defer release(e)
	if !e.live || e.delivery.Attempts != job.Attempt || e.delivery.State != "transmitting" {
		return ErrConflict
	}
	defer func() { e.live = false }()
	if !oneOf(result.State, "handed_off", "retry_wait", "needs_attention", "uncertain") || !token(result.Code, 64) {
		return ErrInvalid
	}
	d := e.delivery
	d.State = result.State
	d.Code = result.Code
	d.UpdatedAt = s.now()
	if d.State == "retry_wait" {
		if s.now().Sub(mustTime(e.record.Receipt.AcceptedAt)) >= 7*24*time.Hour {
			d.State = "needs_attention"
			d.Code = "retry_exhausted"
		} else {
			power := d.Attempts
			if power > 8 {
				power = 8
			}
			delay := time.Minute * time.Duration(1<<power)
			if delay > 6*time.Hour {
				delay = 6 * time.Hour
			}
			d.NextAttempt = s.now().Add(time.Duration(float64(delay) * (0.75 + rand.Float64()*0.5)))
		}
	}
	err := s.check("delivery_finish")
	if err == nil {
		err = s.saveDeliveryLocked(job.ID, e, d)
	}
	if err != nil {
		d.State = "uncertain"
		d.Code = "state_write_failed"
		e.delivery = d
		_ = s.saveDeliveryLocked(job.ID, e, d)
		return ErrUnavailable
	}
	e.delivery = d
	return nil
}

type Stats struct {
	Records                  int   `json:"records"`
	Tombstones               int   `json:"tombstones"`
	Bytes                    int64 `json:"bytes"`
	Pending                  int   `json:"pending"`
	Uncertain                int   `json:"uncertain"`
	NeedsAttention           int   `json:"needsAttention"`
	OldestUndeliveredSeconds int64 `json:"oldestUndeliveredSeconds"`
	ExpiredUndelivered       int   `json:"expiredUndelivered"`
	MaxRecords               int   `json:"maxRecords"`
	MaxBytes                 int64 `json:"maxBytes"`
	ReservedBytes            int64 `json:"reservedBytes"`
	AvailableDiskBytes       int64 `json:"availableDiskBytes"`
	MinFreeBytes             int64 `json:"minFreeBytes"`
	StorageAvailable         bool  `json:"storageAvailable"`
}

func (s *Store) Stats(ctx context.Context) (Stats, error) {
	if !s.begin() {
		return Stats{}, ErrUnavailable
	}
	defer s.ops.Done()
	var stats Stats
	s.mu.Lock()
	stats.Bytes = s.used
	stats.ReservedBytes = s.reserved
	stats.MaxBytes = s.limits.MaxBytes
	stats.MaxRecords = s.limits.MaxRecords
	stats.MinFreeBytes = s.limits.MinFreeBytes
	identities := len(s.entries)
	reservedRecords := s.reservedRecords
	s.mu.Unlock()
	for _, id := range s.IDs() {
		e := s.get(id)
		if e == nil {
			continue
		}
		if err := acquire(ctx, e); err != nil {
			return stats, err
		}
		if e.record.Tombstone {
			stats.Tombstones++
			if e.delivery.Code == "expired_undelivered" {
				stats.ExpiredUndelivered++
			}
		} else {
			stats.Records++
			switch e.delivery.State {
			case "pending", "retry_wait", "transmitting":
				stats.Pending++
			case "uncertain":
				stats.Uncertain++
			case "needs_attention":
				stats.NeedsAttention++
			}
			if e.delivery.State != "handed_off" {
				age := int64(s.now().Sub(mustTime(e.record.Receipt.AcceptedAt)).Seconds())
				if age > stats.OldestUndeliveredSeconds {
					stats.OldestUndeliveredSeconds = age
				}
			}
		}
		release(e)
	}
	available, spaceErr := s.space(s.dir)
	stats.AvailableDiskBytes = available
	stats.StorageAvailable = spaceErr == nil && available-stats.ReservedBytes-reservationBytes >= stats.MinFreeBytes && stats.Bytes+stats.ReservedBytes+reservationBytes+stateReserve <= stats.MaxBytes && stats.Records+reservedRecords < stats.MaxRecords && identities+reservedRecords < s.limits.MaxIdentities
	return stats, nil
}

// RunOutbox exits after its sender observes cancellation. Transport deadlines
// provide the bound even if a relay becomes unresponsive during shutdown.
func RunOutbox(ctx context.Context, s *Store, sender MailSender) {
	nextPrune := time.Time{}
	for ctx.Err() == nil {
		if time.Now().After(nextPrune) {
			if err := s.Prune(ctx); err != nil {
				log.Print("feedback retention unavailable")
			}
			nextPrune = time.Now().Add(time.Minute)
		}
		job, err := s.Claim(ctx)
		if err != nil {
			log.Print("feedback outbox store unavailable")
		}
		if err == nil && job != nil {
			result := sender.Send(ctx, *job)
			finishCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			if err := s.Finish(finishCtx, *job, result); err != nil {
				log.Print("feedback outbox outcome requires inspection")
			}
			cancel()
			if oneOf(result.State, "uncertain", "needs_attention") {
				log.Printf("feedback delivery requires attention receipt=%s", job.ID)
			}
			continue
		}
		timer := time.NewTimer(10 * time.Second)
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.C:
		}
	}
}

// RunRetention preserves private V1 retention after SMTP delivery has drained.
// Public mode must not retain old raw submissions merely because it has no mail
// sender, and this worker never claims or republishes a private submission.
func RunRetention(ctx context.Context, s *Store) {
	for ctx.Err() == nil {
		if err := s.Prune(ctx); err != nil {
			log.Print("feedback retention unavailable")
		}
		timer := time.NewTimer(time.Minute)
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.C:
		}
	}
}

// PrepareLegacyStore completes due private retention before deciding whether
// SMTP is still required. A failed or cancelled cleanup never authorizes startup
// without the legacy sender; expired delivery state is not unfinished work.
func PrepareLegacyStore(ctx context.Context, s *Store) (needsSMTP bool, err error) {
	if err = ctx.Err(); err != nil {
		return false, err
	}
	if err = s.Prune(ctx); err != nil {
		return false, err
	}
	if err = ctx.Err(); err != nil {
		return false, err
	}
	stats, err := s.Stats(ctx)
	if err != nil {
		return false, err
	}
	if err = ctx.Err(); err != nil {
		return false, err
	}
	return stats.Pending > 0 || stats.Uncertain > 0 || stats.NeedsAttention > 0, nil
}
