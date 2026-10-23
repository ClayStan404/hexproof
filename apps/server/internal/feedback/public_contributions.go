// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const maxCasePayload = 32 << 20
const maxReplies = 16
const maxProjections = 32

func contributionFile(caseID, id string) string { return "contrib-" + caseID + "-" + id + ".json" }
func contributionName(name string) (string, string, bool) {
	if len(name) != 86 || !strings.HasPrefix(name, "contrib-") || !strings.HasSuffix(name, ".json") {
		return "", "", false
	}
	a, b := name[8:44], name[45:81]
	return a, b, name[44] == '-' && validID(a) && validID(b)
}
func (s *PublicStore) payload(caseID string, c publicContribution) (publicContributionPayload, error) {
	var p publicContributionPayload
	f, err := os.Open(filepath.Join(s.dir, contributionFile(caseID, c.ID)))
	if err != nil {
		return p, ErrUnavailable
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || !info.Mode().IsRegular() {
		return p, ErrInvalid
	}
	raw, err := readBounded(f, 8<<20)
	if err != nil || decodeClosed(raw, &p) != nil {
		return p, ErrInvalid
	}
	if c.Kind == "reply" {
		if p.Reply == nil || p.Projection != nil || p.Reply.Manifest.SubmissionID != c.ID || p.Reply.Manifest.ParentSubmissionID != caseID || p.Reply.Digest != c.Digest || PublicReplyDigest(p.Reply.ManifestBytes) != c.Digest {
			return p, ErrInvalid
		}
		var m PublicManifest
		if decodeClosed(p.Reply.ManifestBytes, &m) != nil {
			return p, ErrInvalid
		}
		a, _ := json.Marshal(m)
		b, _ := json.Marshal(p.Reply.Manifest)
		if string(a) != string(b) || len(p.Reply.Blobs) != len(m.Attachments) {
			return p, ErrInvalid
		}
		for i, b := range p.Reply.Blobs {
			if b.Attachment != m.Attachments[i] || int64(len(b.Bytes)) != b.Attachment.ByteLength || hashBytes(b.Bytes) != b.Attachment.SHA256 {
				return p, ErrInvalid
			}
		}
	} else if p.Projection == nil || p.Reply != nil || p.Projection.ID != c.ID || (c.Kind == "question") != (p.Projection.Question != nil) || projectionDigest(*p.Projection) != c.Digest {
		return p, ErrInvalid
	}
	return p, nil
}
func projectionDigest(p ProjectionRequest) string {
	raw, _ := json.Marshal(p)
	return hashBytes(append([]byte("hexproof-projection-v1\n"), raw...))
}
func (s *PublicStore) saveContribution(r *PublicRecord, c publicContribution, p publicContributionPayload) error {
	raw, err := json.Marshal(p)
	if err != nil {
		return ErrInvalid
	}
	size := int64(len(raw))
	next := *r
	next.Contributions = append(append([]publicContribution(nil), r.Contributions...), c)
	next.ThreadRevision = max(r.ThreadRevision, s.entries[r.Receipt.SubmissionID].ThreadRevision) + 1
	stateBytes, err := json.Marshal(next)
	if err != nil {
		return ErrInvalid
	}
	stateDelta := int64(len(stateBytes)) - s.sizes[r.Receipt.SubmissionID]
	total := s.sizes[r.Receipt.SubmissionID]
	for _, child := range r.Contributions {
		total += s.sizes[contributionFile(r.Receipt.SubmissionID, child.ID)]
	}
	free, err := freeBytes(s.dir)
	if err != nil {
		return ErrUnavailable
	}
	if total+size+stateDelta > maxCasePayload || s.used+size+stateDelta+reservationBytes+stateReserve > s.limits.MaxBytes || free-size-max(stateDelta, 0)-reservationBytes < s.limits.MinFreeBytes {
		return ErrCapacity
	}
	name := contributionFile(r.Receipt.SubmissionID, c.ID)
	if err := atomicJSON(s.dir, name, p); err != nil {
		s.failed = true
		return ErrUnavailable
	}
	s.sizes[name] = size
	s.used += size
	r.Contributions = append(r.Contributions, c)
	return s.save(*r)
}
func findContribution(r *PublicRecord, id string) *publicContribution {
	for i := range r.Contributions {
		if r.Contributions[i].ID == id {
			return &r.Contributions[i]
		}
	}
	return nil
}
func (s *PublicStore) LookupReply(caseID, id string, secret []byte, digest string) (PublicReceipt, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, err := s.lookup(caseID, secret, "")
	if err != nil {
		return PublicReceipt{}, err
	}
	c := findContribution(&r, id)
	if c == nil || c.Kind != "reply" {
		return PublicReceipt{}, ErrNotFound
	}
	if digest != "" && digest != c.Digest {
		return c.Receipt, ErrConflict
	}
	return childReceipt(r, *c), nil
}
func childReceipt(r PublicRecord, c publicContribution) PublicReceipt {
	v := c.Receipt
	v.IssueURL = r.Receipt.IssueURL
	v.RemovalState = r.Receipt.RemovalState
	v.CaseState = r.Receipt.CaseState
	v.ClosurePublicationState = r.Receipt.ClosurePublicationState
	v.ClosedAt = r.Receipt.ClosedAt
	v.ClosureReason = r.Receipt.ClosureReason
	return v
}
func (s *PublicStore) AcceptReply(caseID string, secret []byte, sub PublicSubmission) (PublicReceipt, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, err := s.lookup(caseID, secret, "")
	if err != nil {
		return PublicReceipt{}, false, err
	}
	if c := findContribution(&r, sub.Manifest.SubmissionID); c != nil {
		if c.Kind != "reply" || c.Digest != sub.Digest {
			return PublicReceipt{}, false, ErrConflict
		}
		return childReceipt(r, *c), false, nil
	}
	if r.Receipt.CaseState == "closed" || r.Receipt.RemovalState != "none" || !s.now().Before(mustTime(r.Receipt.ContentExpiresAt)) {
		return PublicReceipt{}, false, ErrExpired
	}
	r, _, err = s.read(caseID)
	if err != nil {
		return PublicReceipt{}, false, ErrUnavailable
	}
	m := sub.Manifest
	if !validID(m.SubmissionID) || m.SubmissionID == caseID || m.ParentSubmissionID != caseID || PublicReplyDigest(sub.ManifestBytes) != sub.Digest || sub.Target != r.Submission.Target || m.Category != r.Submission.Manifest.Category {
		return PublicReceipt{}, false, ErrInvalid
	}
	n := 0
	for _, c := range r.Contributions {
		if c.Kind == "reply" {
			n++
		}
	}
	if n >= maxReplies {
		return PublicReceipt{}, false, ErrCapacity
	}
	if m.QuestionID != "" {
		found := false
		for _, c := range r.Contributions {
			if c.Kind == "question" && c.Receipt.PublicationState == "published" {
				p, e := s.payload(caseID, c)
				if e != nil {
					return PublicReceipt{}, false, e
				}
				q := p.Projection.Question
				if q != nil && q.ID == m.QuestionID && q.Revision == m.QuestionRevision {
					found = true
				}
			}
		}
		if !found {
			return PublicReceipt{}, false, ErrConflict
		}
	} else if m.QuestionRevision != 0 {
		return PublicReceipt{}, false, ErrInvalid
	}
	receipt := PublicReceipt{SchemaVersion: 2, SubmissionID: m.SubmissionID, ParentSubmissionID: caseID, Receipt: m.SubmissionID, AcceptedAt: s.now().UTC().Format(time.RFC3339Nano), ContentExpiresAt: r.Receipt.ContentExpiresAt, AccessExpiresAt: r.Receipt.AccessExpiresAt, State: "accepted", PublicationState: "pending", RemovalState: "none"}
	c := publicContribution{ID: m.SubmissionID, Sequence: int64(len(r.Contributions) + 2), Kind: "reply", Digest: sub.Digest, Receipt: receipt}
	if err = s.saveContribution(&r, c, publicContributionPayload{Reply: &sub}); err != nil {
		return PublicReceipt{}, false, err
	}
	return childReceipt(r, c), true, nil
}
func (s *PublicStore) ReplyAsset(caseID, id, attachmentID, digest string, target PublicTarget) (Blob, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, ok := s.entries[caseID]
	if !ok || s.failed || s.closed || r.Receipt.RemovalState != "none" || !s.now().Before(mustTime(r.Receipt.ContentExpiresAt)) {
		return Blob{}, ErrNotFound
	}
	c := findContribution(&r, id)
	if c == nil || !c.AssetsVisible || c.Removed {
		return Blob{}, ErrNotFound
	}
	p, err := s.payload(caseID, *c)
	if err != nil {
		return Blob{}, err
	}
	if p.Reply == nil || p.Reply.Target != target {
		return Blob{}, ErrNotFound
	}
	for _, b := range p.Reply.Blobs {
		if b.Attachment.ID == attachmentID && b.Attachment.SHA256 == digest {
			return b, nil
		}
	}
	return Blob{}, ErrNotFound
}
func (s *PublicStore) ListCaseIDs() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	ids := make([]string, 0, len(s.entries))
	if s.failed || s.closed {
		return ids
	}
	for id := range s.entries {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	return ids
}
func (s *PublicStore) loadBridgeCase(id, binding string) (PublicRecord, error) {
	if s.failed || s.closed {
		return PublicRecord{}, ErrUnavailable
	}
	if !validHash(binding) {
		return PublicRecord{}, ErrInvalid
	}
	if _, ok := s.entries[id]; !ok {
		return PublicRecord{}, ErrNotFound
	}
	r, _, err := s.read(id)
	if err != nil {
		return r, ErrUnavailable
	}
	if r.CoordinatorBinding != "" && r.CoordinatorBinding != binding {
		return r, ErrConflict
	}
	return r, nil
}
func (s *PublicStore) ExportCase(id, binding string) (CaseSnapshot, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, err := s.loadBridgeCase(id, binding)
	if err != nil {
		return CaseSnapshot{}, err
	}
	if r.Receipt.RemovalState == "none" && r.Receipt.CaseState != "closed" && r.Receipt.PublicationState != "published" {
		return CaseSnapshot{}, ErrUnavailable
	}
	if r.CoordinatorBinding == "" && r.Receipt.CaseState != "closed" {
		r.CoordinatorBinding = binding
		r.CoordinatorExported = true
		if r.Receipt.RemovalState != "none" {
			r.RevocationRevision = max(r.ThreadRevision+1, 1)
		}
		if err = s.save(r); err != nil {
			return CaseSnapshot{}, err
		}
		r = s.entries[id]
		r, _, err = s.read(id)
		if err != nil {
			return CaseSnapshot{}, err
		}
	}
	return s.caseSnapshotForRecord(r)
}

// The caller holds the store lock and has already checked its export policy.
// Publication observations contain metadata only, including pending projections.
func (s *PublicStore) caseSnapshotForRecord(r PublicRecord) (CaseSnapshot, error) {
	id := r.Receipt.SubmissionID
	out := CaseSnapshot{CaseID: id, SourceRevision: max(r.ThreadRevision, 1), InputRevision: r.InputRevision, IssueURL: r.Receipt.IssueURL, State: "active", Contributions: []CaseContribution{}, Replies: []CaseReplyObservation{}, RevocationRevision: r.RevocationRevision, PublishedProjections: []CasePublicProjection{}, DeliveryHistory: []PublicDeliveryFact{}}
	if r.Receipt.RemovalState != "none" {
		out.State = "removed"
		out.IssueURL = ""
		out.SourceRevision = r.RevocationRevision
		return out, nil
	}
	if r.Receipt.CaseState == "closed" {
		out.State = "closed"
		out.IssueURL = ""
		return out, nil
	}
	if r.Receipt.PublishedAt == "" {
		return CaseSnapshot{}, ErrUnavailable
	}
	out.Contributions = append(out.Contributions, caseContribution(*r.Submission, r.Receipt, id))
	for _, c := range r.Contributions {
		if c.Kind == "reply" {
			p, e := s.payload(id, c)
			if e != nil {
				return out, e
			}
			m := p.Reply.Manifest
			out.Replies = append(out.Replies, CaseReplyObservation{ID: c.ID, QuestionID: m.QuestionID, QuestionRevision: m.QuestionRevision, ReceivedAt: mustTime(c.Receipt.AcceptedAt), PublicationState: observationState(c.Receipt.PublicationState)})
			if c.Receipt.PublicationState == "published" {
				out.Contributions = append(out.Contributions, caseContribution(*p.Reply, c.Receipt, id))
			}
		} else {
			p, e := s.payload(id, c)
			if e != nil {
				return out, e
			}
			projection := p.Projection
			if c.Receipt.PublicationState == "published" {
				out.PublishedProjections = append(out.PublishedProjections, CasePublicProjection{ID: projection.ID, WorkflowRevision: projection.WorkflowRevision, ExpectedInputRevision: projection.ExpectedInputRevision, WorkState: projection.WorkState, Summary: projection.Summary, Question: projection.Question, Outcome: projection.Outcome, PublishedAt: mustTime(c.Receipt.PublishedAt)})
				out.DeliveryHistory = appendDeliveryFact(out.DeliveryHistory, *projection, c.Receipt.PublishedAt)
			}
			if out.LatestProjection == nil || projection.WorkflowRevision > out.LatestProjection.WorkflowRevision {
				out.LatestProjection = &CaseProjectionObservation{ID: projection.ID, WorkflowRevision: projection.WorkflowRevision, ExpectedInputRevision: projection.ExpectedInputRevision, PublicationState: c.Receipt.PublicationState}
			}
			if q := projection.Question; q != nil && c.Receipt.PublicationState == "published" {
				out.QuestionPublication = &CaseQuestionPublication{ID: q.ID, Revision: q.Revision, PublishedAt: s.questionPublishedAt(r, q.ID, q.Revision)}
			}
		}
	}
	return out, nil
}
func caseContribution(sub PublicSubmission, r PublicReceipt, caseID string) CaseContribution {
	m := sub.Manifest
	ctx, _ := json.Marshal(m.Context)
	text := "Description:\n" + m.Description + "\n\nTechnical context:\n" + string(ctx)
	c := CaseContribution{ID: m.SubmissionID, Revision: 1, Digest: sub.Digest, Origin: "feedback-v2", PolicyRevision: m.Disclosure.ProviderPolicyRevision, Provenance: "public-feedback-consent", ReceivedAt: mustTime(r.AcceptedAt), PublishedAt: mustTime(r.PublishedAt), Text: text, Category: m.Category, Description: m.Description, Context: m.Context, Attachments: []CaseAttachment{}}
	for _, a := range m.Attachments {
		c.Attachments = append(c.Attachments, CaseAttachment{URL: contributionAssetURL(sub.Target.PublicURL, caseID, m.ParentSubmissionID != "", m.SubmissionID, a), SHA256: a.SHA256, MediaType: a.MediaType})
	}
	return c
}
func contributionAssetURL(base, caseID string, reply bool, id string, a Attachment) string {
	path := base + "/assets/" + caseID + "/"
	if reply {
		path += "replies/" + id + "/"
	}
	return path + a.ID + "/" + a.SHA256
}
func (s *PublicStore) EnqueueProjection(id, binding string, p ProjectionRequest) (ProjectionReceipt, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, err := s.loadBridgeCase(id, binding)
	if err != nil {
		return ProjectionReceipt{}, err
	}
	if !r.CoordinatorExported || r.CoordinatorBinding != binding {
		return ProjectionReceipt{}, ErrConflict
	}
	if r.Receipt.CaseState == "closed" {
		return ProjectionReceipt{}, ErrExpired
	}
	digest := projectionDigest(p)
	if c := findContribution(&r, p.ID); c != nil {
		if c.Digest != digest {
			return ProjectionReceipt{}, ErrConflict
		}
		return ProjectionReceipt{ID: p.ID, PublicationState: c.Receipt.PublicationState, PublishedAt: c.Receipt.PublishedAt}, nil
	}
	if r.Receipt.RemovalState != "none" || !s.now().Before(mustTime(r.Receipt.ContentExpiresAt)) {
		return ProjectionReceipt{}, ErrExpired
	}
	if !validID(p.ID) || p.ID == id || p.WorkflowRevision < 1 || p.ExpectedInputRevision != r.InputRevision || !oneOf(p.WorkState, "new", "assessing", "needs-information", "ready", "implementing", "verifying", "verified-awaiting-review", "reviewing", "verifying-integration", "merge-ready", "merging", "merged-awaiting-release", "source-published-awaiting-release", "released", "duplicate", "declined", "deferred", "blocked") || len(p.Summary) > 4096 || publicCredentialPattern.MatchString(p.Summary) {
		return ProjectionReceipt{}, ErrInvalid
	}
	if !validProjectionOutcome(p, r.Submission.Target.Repository, r.IssueNumber) {
		return ProjectionReceipt{}, ErrInvalid
	}
	n := 0
	var latest int64
	for _, c := range r.Contributions {
		if c.Kind != "reply" {
			n++
			old, e := s.payload(id, c)
			if e != nil {
				return ProjectionReceipt{}, e
			}
			latest = max(latest, old.Projection.WorkflowRevision)
			if q, previous := p.Question, old.Projection.Question; q != nil && previous != nil && q.ID == previous.ID && q.Revision == previous.Revision && *q != *previous {
				return ProjectionReceipt{}, ErrConflict
			}
		}
	}
	if n >= maxProjections {
		return ProjectionReceipt{}, ErrCapacity
	}
	if p.WorkflowRevision <= latest {
		return ProjectionReceipt{}, ErrConflict
	}
	kind := "assessment"
	if q := p.Question; q != nil {
		if !validID(q.ID) || q.Revision < 1 || q.Revision > 1000000 || !oneOf(q.Code, "custom", "reproduction_steps", "expected_actual", "affected_version", "platform", "minimal_public_example", "user_goal") || q.Description == "" || len(q.Description) > 4096 || publicCredentialPattern.MatchString(q.Description) || q.TimeoutSeconds < 60 || q.TimeoutSeconds > 30*86400 {
			return ProjectionReceipt{}, ErrInvalid
		}
		kind = "question"
	}
	c := publicContribution{ID: p.ID, Sequence: int64(len(r.Contributions) + 2), Kind: kind, Digest: digest, Receipt: PublicReceipt{SchemaVersion: 2, SubmissionID: p.ID, ParentSubmissionID: id, Receipt: p.ID, AcceptedAt: s.now().UTC().Format(time.RFC3339Nano), ContentExpiresAt: r.Receipt.ContentExpiresAt, AccessExpiresAt: r.Receipt.AccessExpiresAt, State: "accepted", PublicationState: "pending", RemovalState: "none"}}
	if err = s.saveContribution(&r, c, publicContributionPayload{Projection: &p}); err != nil {
		return ProjectionReceipt{}, err
	}
	return ProjectionReceipt{ID: p.ID, PublicationState: "pending"}, nil
}
func (s *PublicStore) AcknowledgeRevocation(id, binding string, revision int64) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, err := s.loadBridgeCase(id, binding)
	if err != nil {
		return err
	}
	if !r.CoordinatorExported || r.CoordinatorBinding != binding || r.Receipt.RemovalState == "none" || revision < 1 || r.RevocationRevision != revision {
		return ErrConflict
	}
	if r.RevocationAcknowledged {
		return nil
	}
	r.RevocationAcknowledged = true
	if r.ExternalRemoved {
		s.markRemoved(&r)
	}
	if err = s.save(r); err != nil {
		return err
	}
	if r.Receipt.RemovalState == "removed" {
		return s.purgeContributions(r)
	}
	return nil
}
func (s *PublicStore) startRemoval(r *PublicRecord, reason string) {
	r.AssetsVisible = false
	r.Receipt.RemovalState = "requested"
	r.Receipt.Reason = reason
	r.Attempts = 0
	r.NextAttempt = time.Time{}
	if r.CoordinatorExported && r.RevocationRevision == 0 {
		r.RevocationRevision = max(r.ThreadRevision+1, 1)
	}
	for i := range r.Contributions {
		c := &r.Contributions[i]
		c.AssetsVisible = false
		c.Attempts = 0
		c.NextAttempt = time.Time{}
		if c.CommentID == 0 && !c.CreateUncertain && r.ActiveContributionID != c.ID {
			c.Removed = true
		}
	}
}
func (s *PublicStore) markRemoved(r *PublicRecord) {
	r.ExternalRemoved = true
	r.AssetsVisible = false
	if r.CoordinatorExported && !r.RevocationAcknowledged {
		r.Receipt.RemovalState = "pending"
		r.Receipt.Reason = "coordinator_cleanup_pending"
		return
	}
	r.Receipt.RemovalState = "removed"
	r.Receipt.Reason = ""
	r.RemovedAt = s.now()
	r.Submission = nil
}
func (s *PublicStore) purgeContributions(r PublicRecord) error {
	for _, c := range r.Contributions {
		name := contributionFile(r.Receipt.SubmissionID, c.ID)
		if err := os.Remove(filepath.Join(s.dir, name)); err != nil && !os.IsNotExist(err) {
			s.failed = true
			return ErrUnavailable
		}
		s.used -= s.sizes[name]
		delete(s.sizes, name)
	}
	if err := syncDirectory(s.dir); err != nil {
		s.failed = true
		return ErrUnavailable
	}
	return nil
}
func (s *PublicStore) recoverContributions(items []os.DirEntry) error {
	refs := map[string]bool{}
	for id, meta := range s.entries {
		r := meta
		if len(r.Contributions) > 0 && r.Receipt.RemovalState != "removed" {
			var err error
			r, _, err = s.read(id)
			if err != nil {
				return err
			}
		}
		if len(r.Contributions) > maxReplies+maxProjections {
			return ErrInvalid
		}
		seen := map[string]bool{}
		for i, c := range r.Contributions {
			if !validID(c.ID) || c.ID == id || seen[c.ID] || c.Sequence != int64(i+2) || !oneOf(c.Kind, "reply", "assessment", "question") || !validHash(c.Digest) || c.Receipt.SubmissionID != c.ID || c.Receipt.ParentSubmissionID != id || c.Attempts < 0 || c.Attempts > 12 || c.Receipt.SchemaVersion != 2 || c.Receipt.Receipt != c.ID || c.Receipt.State != "accepted" || !utcTime(c.Receipt.AcceptedAt) || c.Receipt.ContentExpiresAt != r.Receipt.ContentExpiresAt || c.Receipt.AccessExpiresAt != r.Receipt.AccessExpiresAt || !oneOf(c.Receipt.PublicationState, "pending", "partial", "published", "stalled", "rejected") || c.Receipt.PublicationState == "published" && !utcTime(c.Receipt.PublishedAt) || c.Receipt.PublishedAt != "" && !utcTime(c.Receipt.PublishedAt) {
				return ErrInvalid
			}
			seen[c.ID] = true
			if r.Receipt.RemovalState == "removed" {
				continue
			}
			name := contributionFile(id, c.ID)
			refs[name] = true
			p, err := s.payload(id, c)
			if err != nil {
				return err
			}
			if p.Reply != nil && (r.Submission == nil || p.Reply.Target != r.Submission.Target) {
				return ErrInvalid
			}
			info, err := os.Stat(filepath.Join(s.dir, name))
			if err != nil {
				return err
			}
			s.sizes[name] = info.Size()
			s.used += info.Size()
		}
	}
	for _, item := range items {
		if _, _, ok := contributionName(item.Name()); ok && !refs[item.Name()] {
			if err := os.Remove(filepath.Join(s.dir, item.Name())); err != nil {
				return err
			}
		}
	}
	return nil
}
func (s *PublicStore) contributionJob(r *PublicRecord) (*PublicJob, error) {
	removal := r.Receipt.RemovalState != "none"
	for i := range r.Contributions {
		c := &r.Contributions[i]
		if removal {
			if c.Removed {
				continue
			}
		} else if oneOf(c.Receipt.PublicationState, "published", "stalled", "rejected") {
			continue
		}
		if s.now().Before(c.NextAttempt) {
			return nil, nil
		}
		if c.Attempts >= 12 || !removal && s.now().Sub(mustTime(c.Receipt.AcceptedAt)) >= 7*24*time.Hour {
			if removal {
				r.Receipt.RemovalState = "stalled"
				r.StalledAt = s.now()
				r.Receipt.Reason = "reply_removal_exhausted"
			} else {
				c.Receipt.PublicationState = "stalled"
				c.Receipt.Reason = "retry_exhausted"
			}
			return nil, s.save(*r)
		}
		payload, err := s.payload(r.Receipt.SubmissionID, *c)
		if err != nil {
			return nil, err
		}
		action := "comment-create"
		if c.CreateUncertain {
			action = "comment-reconcile"
		} else if c.CommentID > 0 {
			action = "comment-verify"
		}
		if !removal && r.Receipt.CaseState == "closed" && c.Kind != "reply" && action == "comment-create" {
			c.Receipt.PublicationState = "rejected"
			c.Receipt.Reason = "case_closed"
			return nil, s.save(*r)
		}
		if removal && !c.CreateUncertain {
			if c.CommentID == 0 {
				c.Removed = true
				return nil, s.save(*r)
			}
			action = "comment-remove"
		}
		if action == "comment-create" {
			c.AssetsVisible = true
		}
		c.Attempts++
		c.NextAttempt = time.Time{}
		r.InFlight = true
		r.Action = action
		r.ActiveContributionID = c.ID
		r.Generation++
		if err = s.save(*r); err != nil {
			return nil, err
		}
		s.live[r.Receipt.SubmissionID] = true
		copy := *c
		return &PublicJob{ID: r.Receipt.SubmissionID, Record: *r, Action: action, Generation: r.Generation, Contribution: &copy, Payload: &payload}, nil
	}
	return nil, nil
}
func (s *PublicStore) finishContribution(r *PublicRecord, job PublicJob, result PublicResult) error {
	c := findContribution(r, job.Contribution.ID)
	if c == nil || r.ActiveContributionID != c.ID {
		return ErrConflict
	}
	r.ActiveContributionID = ""
	r.InFlight = false
	r.Action = ""
	if result.CommentID > 0 {
		c.CommentID = result.CommentID
		c.CommentNodeID = result.CommentNodeID
		c.CreateUncertain = false
	}
	removal := r.Receipt.RemovalState != "none"
	switch result.Outcome {
	case "verified":
		if !removal {
			if c.Receipt.PublicationState != "published" && c.Kind == "reply" {
				r.InputRevision++
			}
			c.Receipt.PublicationState = "published"
			c.Receipt.Reason = ""
			c.Receipt.PublishedAt = s.now().UTC().Format(time.RFC3339Nano)
		}
	case "mapped":
		c.Receipt.PublicationState = "partial"
		c.Receipt.Reason = "verification_pending"
	case "removed":
		if !removal {
			return ErrInvalid
		}
		c.Removed = true
		c.AssetsVisible = false
	case "uncertain":
		c.CreateUncertain = true
		c.Receipt.Reason = result.Code
	case "retry":
		c.Receipt.Reason = result.Code
	case "stalled":
		c.Receipt.Reason = result.Code
		if removal {
			r.Receipt.RemovalState = "stalled"
			r.StalledAt = s.now()
			r.Receipt.Reason = result.Code
		} else {
			c.Receipt.PublicationState = "stalled"
		}
	default:
		return ErrInvalid
	}
	if !oneOf(result.Outcome, "verified", "mapped", "removed", "stalled") {
		c.NextAttempt = s.now().Add(min(max(time.Minute*time.Duration(1<<min(c.Attempts, 8)), result.RetryAfter), 6*time.Hour))
	}
	if removal && c.CommentID == 0 && !c.CreateUncertain && oneOf(result.Outcome, "retry", "stalled") {
		c.Removed = true
		r.Receipt.RemovalState = "pending"
	}
	return s.save(*r)
}

func observationState(state string) string {
	if state == "partial" {
		return "pending"
	}
	return state
}

func (s *PublicStore) questionPublishedAt(r PublicRecord, id string, revision int64) time.Time {
	for _, c := range r.Contributions {
		if c.Kind == "question" && c.Receipt.PublicationState == "published" {
			p, err := s.payload(r.Receipt.SubmissionID, c)
			if err == nil && p.Projection.Question.ID == id && p.Projection.Question.Revision == revision {
				return mustTime(c.Receipt.PublishedAt)
			}
		}
	}
	return time.Time{}
}

// MarkAssessmentDelivery records transport health, never an assessment result.
// Repeated failures do not produce writes or reset any durable execution budget.
func (s *PublicStore) MarkAssessmentDelivery(id, binding string, available bool, reason string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.failed || s.closed {
		return ErrUnavailable
	}
	if !validID(id) || !validHash(binding) || !token(reason, 64) {
		return ErrInvalid
	}
	meta, ok := s.entries[id]
	if !ok {
		return ErrNotFound
	}
	if meta.Receipt.RemovalState == "removed" {
		return nil
	}
	state := "unavailable"
	if available {
		state = "available"
		reason = ""
		if !meta.CoordinatorExported || meta.CoordinatorBinding != binding {
			return ErrConflict
		}
	} else if meta.CoordinatorBinding != "" && meta.CoordinatorBinding != binding {
		reason = "assessment_target_changed"
	}
	if meta.AssessmentDeliveryState == state && meta.AssessmentDeliveryReason == reason {
		return nil
	}
	r, _, err := s.read(id)
	if err != nil {
		return ErrUnavailable
	}
	r.AssessmentDeliveryState = state
	r.AssessmentDeliveryReason = reason
	if available {
		r.AssessmentUnavailableAt = time.Time{}
	} else if r.AssessmentUnavailableAt.IsZero() {
		r.AssessmentUnavailableAt = s.now()
	}
	return s.save(r)
}
