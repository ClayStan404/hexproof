// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

var ErrThreadChanged = errors.New("thread_changed")

func (s *PublicStore) Thread(id string, secret []byte, cursor string, limit int) (PublicThread, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, err := s.lookup(id, secret, "")
	if err != nil {
		return PublicThread{}, err
	}
	r, _, err = s.read(id)
	if err != nil {
		return PublicThread{}, ErrUnavailable
	}
	out := PublicThread{AssessmentDeliveryState: r.AssessmentDeliveryState, AssessmentDeliveryReason: r.AssessmentDeliveryReason, SchemaVersion: 2, SubmissionID: id, Revision: max(r.ThreadRevision, 1), Items: []ThreadItem{}, WorkState: "new", ProjectionState: "none", RemovalState: r.Receipt.RemovalState, Reason: r.Receipt.Reason, ContentExpiresAt: r.Receipt.ContentExpiresAt, AccessExpiresAt: r.Receipt.AccessExpiresAt}
	out.CaseState = r.Receipt.CaseState
	out.ClosurePublicationState = r.Receipt.ClosurePublicationState
	out.ClosedAt = r.Receipt.ClosedAt
	out.ClosureReason = r.Receipt.ClosureReason
	out.DeliveryHistory = []PublicDeliveryFact{}
	if limit < 1 || limit > 5 {
		return out, ErrInvalid
	}
	var after int64
	if cursor != "" {
		parts := strings.Split(cursor, ":")
		if len(parts) != 2 {
			return out, ErrInvalid
		}
		rev, e := strconv.ParseInt(parts[0], 10, 64)
		if e != nil || rev < 1 {
			return out, ErrInvalid
		}
		after, e = strconv.ParseInt(parts[1], 10, 64)
		if e != nil || after < 1 || after > 49 {
			return out, ErrInvalid
		}
		if rev != out.Revision {
			return out, ErrThreadChanged
		}
	}
	if r.Receipt.RemovalState != "none" {
		return out, nil
	}
	items := make([]ThreadItem, 0, len(r.Contributions)+1)
	if r.Submission != nil {
		items = append(items, submissionThreadItem(*r.Submission, r.Receipt, id, 1))
	}
	for _, c := range r.Contributions {
		p, e := s.payload(id, c)
		if e != nil {
			return out, e
		}
		if c.Kind == "reply" {
			items = append(items, submissionThreadItem(*p.Reply, c.Receipt, id, c.Sequence))
			continue
		}
		current := r.Receipt.CaseState != "closed" && p.Projection.ExpectedInputRevision == r.InputRevision
		if current {
			out.ProjectionState = c.Receipt.PublicationState
		}
		if c.Receipt.PublicationState != "published" {
			continue
		}
		projection := p.Projection
		out.DeliveryHistory = appendDeliveryFact(out.DeliveryHistory, *projection, c.Receipt.PublishedAt)
		if current {
			out.WorkState = projection.WorkState
			out.Summary = projection.Summary
			out.WorkflowRevision = projection.WorkflowRevision
			out.Question = nil
			out.Outcome = projection.Outcome
		}
		item := ThreadItem{SubmissionID: c.ID, ParentSubmissionID: id, Sequence: c.Sequence, Kind: c.Kind, Description: projection.Summary, Attachments: []ThreadAttachment{}, AcceptedAt: c.Receipt.AcceptedAt, PublishedAt: c.Receipt.PublishedAt, PublicationState: "published"}
		item.Outcome = projection.Outcome
		if q := projection.Question; q != nil {
			item.QuestionID = q.ID
			item.QuestionRevision = q.Revision
			item.Description = q.Description
			if current {
				out.Question = &ThreadQuestion{ID: q.ID, Revision: q.Revision, Code: q.Code, Description: q.Description, PublishedAt: s.questionPublishedAt(r, q.ID, q.Revision).Format(time.RFC3339Nano), AnswerDeadline: s.questionPublishedAt(r, q.ID, q.Revision).Add(time.Duration(q.TimeoutSeconds) * time.Second).Format(time.RFC3339Nano)}
			}
		}
		items = append(items, item)
	}
	for _, item := range items {
		if item.Sequence <= after {
			continue
		}
		if len(out.Items) == limit {
			out.NextCursor = fmt.Sprintf("%d:%d", out.Revision, out.Items[len(out.Items)-1].Sequence)
			break
		}
		out.Items = append(out.Items, item)
	}
	return out, nil
}
func submissionThreadItem(sub PublicSubmission, r PublicReceipt, caseID string, sequence int64) ThreadItem {
	m := sub.Manifest
	kind := "submission"
	if m.ParentSubmissionID != "" {
		kind = "reply"
	}
	out := ThreadItem{SubmissionID: m.SubmissionID, ParentSubmissionID: m.ParentSubmissionID, Sequence: sequence, Kind: kind, Category: m.Category, Description: m.Description, Context: m.Context, Disclosure: &m.Disclosure, Attachments: []ThreadAttachment{}, AcceptedAt: r.AcceptedAt, PublishedAt: r.PublishedAt, PublicationState: r.PublicationState, Reason: r.Reason, QuestionID: m.QuestionID, QuestionRevision: m.QuestionRevision}
	for _, a := range m.Attachments {
		out.Attachments = append(out.Attachments, ThreadAttachment{Attachment: a, URL: contributionAssetURL(sub.Target.PublicURL, caseID, kind == "reply", m.SubmissionID, a)})
	}
	return out
}
func (h *PublicHandler) thread(w http.ResponseWriter, r *http.Request, id string, secret []byte) {
	if r.Method != "GET" {
		writePublicError(w, 405, "method_not_allowed")
		return
	}
	q, err := parseThreadQuery(r)
	if err != nil {
		writePublicError(w, 400, "invalid_cursor")
		return
	}
	select {
	case h.controls.queries <- struct{}{}:
		defer func() { <-h.controls.queries }()
	default:
		writePublicError(w, 503, "service_unavailable")
		return
	}
	thread, err := h.store.Thread(id, secret, q.cursor, q.limit)
	if errors.Is(err, ErrThreadChanged) {
		writePublicError(w, 409, "thread_changed")
		return
	}
	if err != nil {
		writePublicStoreError(w, err)
		return
	}
	raw, err := json.Marshal(thread)
	if err != nil || len(raw) > 128<<10 {
		writePublicError(w, 503, "service_unavailable")
		return
	}
	_ = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(30 * time.Second))
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(200)
	_, _ = w.Write(raw)
}

type threadQuery struct {
	cursor string
	limit  int
}

func parseThreadQuery(r *http.Request) (threadQuery, error) {
	q := threadQuery{limit: 5}
	values, err := url.ParseQuery(r.URL.RawQuery)
	if err != nil {
		return q, ErrInvalid
	}
	for k, v := range values {
		if !oneOf(k, "cursor", "limit") || len(v) != 1 {
			return q, ErrInvalid
		}
	}
	q.cursor = values.Get("cursor")
	if len(q.cursor) > 64 {
		return q, ErrInvalid
	}
	if raw := values.Get("limit"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 || n > 5 {
			return q, ErrInvalid
		}
		q.limit = n
	}
	return q, nil
}
