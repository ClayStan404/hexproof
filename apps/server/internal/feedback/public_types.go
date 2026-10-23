// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"time"
)

// PublicManifest is deliberately independent of the legacy private contract.
// Disclosure is part of the immutable, user-approved publication unit.
type PublicDisclosure struct {
	Revision               string `json:"revision"`
	SHA256                 string `json:"sha256"`
	Repository             string `json:"repository"`
	ProviderPolicyRevision string `json:"providerPolicyRevision"`
}
type PublicManifest struct {
	SchemaVersion      int              `json:"schemaVersion"`
	SubmissionID       string           `json:"submissionId"`
	ParentSubmissionID string           `json:"parentSubmissionId,omitempty"`
	QuestionID         string           `json:"questionId,omitempty"`
	QuestionRevision   int64            `json:"questionRevision,omitempty"`
	CreatedAt          string           `json:"createdAt"`
	Category           string           `json:"category"`
	Description        string           `json:"description"`
	Context            Context          `json:"context"`
	Attachments        []Attachment     `json:"attachments"`
	Disclosure         PublicDisclosure `json:"disclosure"`
}
type PublicTarget struct {
	Repository       string `json:"repository"`
	RepositoryID     int64  `json:"repositoryId"`
	PublisherActorID int64  `json:"publisherActorId"`
	PublicURL        string `json:"publicUrl"`
}
type PublicSubmission struct {
	Target        PublicTarget   `json:"target"`
	Manifest      PublicManifest `json:"manifest"`
	ManifestBytes []byte         `json:"manifestBytes"`
	Digest        string         `json:"digest"`
	Blobs         []Blob         `json:"blobs"`
}
type PublicReceipt struct {
	SchemaVersion           int    `json:"schemaVersion"`
	ParentSubmissionID      string `json:"parentSubmissionId,omitempty"`
	PublishedAt             string `json:"publishedAt,omitempty"`
	SubmissionID            string `json:"submissionId"`
	Receipt                 string `json:"receipt"`
	AcceptedAt              string `json:"acceptedAt"`
	ContentExpiresAt        string `json:"contentExpiresAt"`
	AccessExpiresAt         string `json:"accessExpiresAt"`
	State                   string `json:"state"`
	PublicationState        string `json:"publicationState"`
	RemovalState            string `json:"removalState"`
	CaseState               string `json:"caseState"`
	ClosurePublicationState string `json:"closurePublicationState"`
	ClosedAt                string `json:"closedAt,omitempty"`
	ClosureReason           string `json:"closureReason,omitempty"`
	IssueURL                string `json:"issueUrl,omitempty"`
	Reason                  string `json:"reason,omitempty"`
}
type PublicRecord struct {
	MulticaDelivery          *MulticaDelivery     `json:"multicaDelivery,omitempty"`
	AssessmentDeliveryState  string               `json:"assessmentDeliveryState,omitempty"`
	AssessmentDeliveryReason string               `json:"assessmentDeliveryReason,omitempty"`
	AssessmentUnavailableAt  time.Time            `json:"assessmentUnavailableAt,omitempty"`
	PublicationTimeMigrated  bool                 `json:"publicationTimeMigrated,omitempty"`
	ThreadRevision           int64                `json:"threadRevision,omitempty"`
	InputRevision            int64                `json:"inputRevision,omitempty"`
	Contributions            []publicContribution `json:"contributions,omitempty"`
	ActiveContributionID     string               `json:"activeContributionId,omitempty"`
	CoordinatorBinding       string               `json:"coordinatorBinding,omitempty"`
	CoordinatorExported      bool                 `json:"coordinatorExported,omitempty"`
	RevocationRevision       int64                `json:"revocationRevision,omitempty"`
	RevocationAcknowledged   bool                 `json:"revocationAcknowledged,omitempty"`
	ExternalRemoved          bool                 `json:"externalRemoved,omitempty"`
	Receipt                  PublicReceipt        `json:"receipt"`
	SecretHash               string               `json:"secretHash"`
	Digest                   string               `json:"digest"`
	Submission               *PublicSubmission    `json:"submission,omitempty"`
	IssueNumber              int                  `json:"issueNumber,omitempty"`
	IssueNodeID              string               `json:"issueNodeId,omitempty"`
	AssetsVisible            bool                 `json:"assetsVisible,omitempty"`
	CreateUncertain          bool                 `json:"createUncertain,omitempty"`
	Action                   string               `json:"action,omitempty"`
	InFlight                 bool                 `json:"inFlight,omitempty"`
	Attempts                 int                  `json:"attempts"`
	Generation               int                  `json:"generation"`
	RemovalRepairs           int                  `json:"removalRepairs"`
	StalledAt                time.Time            `json:"stalledAt,omitempty"`
	RemovedAt                time.Time            `json:"removedAt,omitempty"`
	NextAttempt              time.Time            `json:"nextAttempt,omitempty"`
	CloseAttempts            int                  `json:"closeAttempts,omitempty"`
	CloseNextAttempt         time.Time            `json:"closeNextAttempt,omitempty"`
}
type PublicJob struct {
	ID           string
	Record       PublicRecord
	Action       string
	Generation   int
	Contribution *publicContribution
	Payload      *publicContributionPayload
}
type PublicResult struct {
	// Outcome is verified, mapped, uncertain, retry, stalled, removed, or closed.
	RetryAfter    time.Duration
	Outcome       string
	Code          string
	IssueNumber   int
	CommentID     int64
	CommentNodeID string
	IssueNodeID   string
	IssueURL      string
}
type PublicPublisher interface {
	Publish(context.Context, PublicJob) PublicResult
}

func PublicDigest(raw []byte) string {
	h := sha256.New()
	h.Write([]byte("hexproof-feedback-v2\n"))
	h.Write(raw)
	return hex.EncodeToString(h.Sum(nil))
}

func PublicReplyDigest(raw []byte) string {
	h := sha256.New()
	h.Write([]byte("hexproof-feedback-reply-v2\n"))
	h.Write(raw)
	return hex.EncodeToString(h.Sum(nil))
}
