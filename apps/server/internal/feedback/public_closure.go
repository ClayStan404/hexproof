// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"net/http"
	"time"
)

func normalizeCaseReceipt(r *PublicReceipt) {
	if r.CaseState == "" {
		r.CaseState = "open"
	}
	if r.ClosurePublicationState == "" {
		r.ClosurePublicationState = "none"
	}
}

func validCaseClosure(r PublicRecord) bool {
	v := r.Receipt
	if r.CloseAttempts < 0 || r.CloseAttempts > 12 || !token(v.ClosureReason, 64) {
		return false
	}
	if v.CaseState == "open" {
		return v.ClosurePublicationState == "none" && v.ClosedAt == "" && v.ClosureReason == "" && r.CloseAttempts == 0 && r.CloseNextAttempt.IsZero()
	}
	return v.CaseState == "closed" && utcTime(v.ClosedAt) && oneOf(v.ClosurePublicationState, "pending", "closed", "stalled")
}

// CloseCase stops admission and content export; retained history and the
// independently delivered GitHub closure are deliberately not purge claims.
func (s *PublicStore) CloseCase(id string, secret []byte) (PublicReceipt, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, err := s.lookup(id, secret, "")
	if err != nil {
		return PublicReceipt{}, err
	}
	if r.Receipt.CaseState == "closed" {
		return r.Receipt, nil
	}
	if r.Receipt.RemovalState != "none" || !s.now().Before(mustTime(r.Receipt.ContentExpiresAt)) {
		return PublicReceipt{}, ErrExpired
	}
	r, _, err = s.read(id)
	if err != nil {
		return PublicReceipt{}, ErrUnavailable
	}
	r.Receipt.CaseState = "closed"
	r.Receipt.ClosedAt = s.now().UTC().Format(time.RFC3339Nano)
	r.Receipt.ClosurePublicationState = "pending"
	r.InputRevision++
	// An admitted/uncertain write must still be reconciled. Unadmitted official
	// follow-up is suppressed without deleting its retained local history.
	for i := range r.Contributions {
		c := &r.Contributions[i]
		if c.Kind != "reply" && c.CommentID == 0 && !c.CreateUncertain && r.ActiveContributionID != c.ID && !oneOf(c.Receipt.PublicationState, "published", "stalled", "rejected") {
			c.Receipt.PublicationState = "rejected"
			c.Receipt.Reason = "case_closed"
		}
	}
	if err = s.save(r); err != nil {
		return PublicReceipt{}, err
	}
	return r.Receipt, nil
}

func closurePending(r PublicRecord) bool {
	return r.Receipt.CaseState == "closed" && r.Receipt.ClosurePublicationState == "pending" && r.Receipt.RemovalState == "none"
}

// The caller holds the store lock. Existing accepted publications retain their
// own finite retry budget; closure never creates a second publication intent.
func (s *PublicStore) closureJob(r *PublicRecord) (*PublicJob, error) {
	if !closurePending(*r) {
		return nil, nil
	}
	unresolved := r.CreateUncertain
	for _, c := range r.Contributions {
		if !oneOf(c.Receipt.PublicationState, "published", "stalled", "rejected") {
			if oneOf(r.Receipt.PublicationState, "stalled", "rejected") {
				unresolved = true
				break
			}
			return nil, nil
		}
		unresolved = unresolved || c.CreateUncertain
	}
	if unresolved {
		r.Receipt.ClosurePublicationState = "stalled"
		r.Receipt.ClosureReason = "publication_unresolved"
		return nil, s.save(*r)
	}
	if r.IssueNumber == 0 {
		r.Receipt.ClosurePublicationState = "closed"
		return nil, s.save(*r)
	}
	if r.CloseAttempts >= 12 || s.now().Sub(mustTime(r.Receipt.ClosedAt)) >= 7*24*time.Hour {
		r.Receipt.ClosurePublicationState = "stalled"
		r.Receipt.ClosureReason = "closure_retry_exhausted"
		return nil, s.save(*r)
	}
	if s.now().Before(r.CloseNextAttempt) {
		return nil, nil
	}
	r.CloseAttempts++
	r.CloseNextAttempt = time.Time{}
	r.InFlight = true
	r.Action = "close"
	r.Generation++
	if err := s.save(*r); err != nil {
		return nil, err
	}
	s.live[r.Receipt.SubmissionID] = true
	return &PublicJob{ID: r.Receipt.SubmissionID, Record: *r, Action: "close", Generation: r.Generation}, nil
}

func (s *PublicStore) finishClosure(r *PublicRecord, result PublicResult) error {
	if r.Receipt.CaseState != "closed" || !oneOf(result.Outcome, "closed", "retry", "stalled", "uncertain") {
		return ErrInvalid
	}
	r.InFlight = false
	r.Action = ""
	r.Receipt.ClosureReason = result.Code
	switch result.Outcome {
	case "closed":
		r.Receipt.ClosurePublicationState = "closed"
		r.Receipt.ClosureReason = ""
	case "stalled":
		r.Receipt.ClosurePublicationState = "stalled"
	default:
		r.CloseNextAttempt = s.now().Add(min(max(time.Minute*time.Duration(1<<min(r.CloseAttempts, 8)), result.RetryAfter), 6*time.Hour))
	}
	return s.save(*r)
}

func (h *PublicHandler) closeCase(w http.ResponseWriter, r *http.Request, id string, secret []byte) {
	if _, err := h.store.Lookup(id, secret, ""); err != nil {
		writePublicStoreError(w, err)
		return
	}
	_ = http.NewResponseController(w).SetReadDeadline(time.Now().Add(5 * time.Second))
	raw, err := readBounded(r.Body, 1)
	if err != nil || len(raw) != 0 || r.Header.Get("Content-Encoding") != "" {
		writePublicError(w, 400, "invalid_request")
		return
	}
	receipt, err := h.store.CloseCase(id, secret)
	if err != nil {
		writePublicStoreError(w, err)
		return
	}
	writeJSON(w, 200, receipt)
}
