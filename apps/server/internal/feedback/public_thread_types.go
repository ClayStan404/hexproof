// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import "time"

// ProjectionRequest is a trusted publication input independent of an AI platform.
// It is never decoded from a public receiver endpoint.
type ProjectionRequest struct {
	ID                    string              `json:"id"`
	WorkflowRevision      int64               `json:"workflowRevision"`
	ExpectedInputRevision int64               `json:"expectedInputRevision"`
	WorkState             string              `json:"workState"`
	Summary               string              `json:"summary"`
	Question              *ProjectionQuestion `json:"question,omitempty"`
	Outcome               *PublicOutcome      `json:"outcome,omitempty"`
}
type ProjectionQuestion struct {
	ID             string `json:"id"`
	Revision       int64  `json:"revision"`
	Code           string `json:"code"`
	Description    string `json:"description"`
	TimeoutSeconds int    `json:"timeoutSeconds"`
}
type ProjectionReceipt struct {
	ID               string `json:"id"`
	PublicationState string `json:"publicationState"`
	PublishedAt      string `json:"publishedAt,omitempty"`
}

// PublicOutcome carries only references inside the configured public repository.
// A projection is not visible as a delivered result until its references and
// official comment have been independently read back from GitHub.
type PublicOutcome struct {
	Kind        string `json:"kind"`
	Repository  string `json:"repository"`
	IssueNumber int    `json:"issueNumber,omitempty"`
	Commit      string `json:"commit,omitempty"`
	Tag         string `json:"tag,omitempty"`
	Version     string `json:"version,omitempty"`
}
type PublicDeliveryFact struct {
	ProjectionID     string        `json:"projectionId"`
	InputRevision    int64         `json:"inputRevision"`
	WorkflowRevision int64         `json:"workflowRevision"`
	PublishedAt      string        `json:"publishedAt"`
	Outcome          PublicOutcome `json:"outcome"`
}
type ThreadQuestion struct {
	ID             string `json:"id"`
	Revision       int64  `json:"revision"`
	Code           string `json:"code"`
	Description    string `json:"description"`
	PublishedAt    string `json:"publishedAt"`
	AnswerDeadline string `json:"answerDeadline"`
}
type ThreadAttachment struct {
	Attachment
	URL string `json:"url"`
}
type ThreadItem struct {
	SubmissionID       string             `json:"submissionId"`
	ParentSubmissionID string             `json:"parentSubmissionId,omitempty"`
	Sequence           int64              `json:"sequence"`
	Kind               string             `json:"kind"`
	Category           string             `json:"category,omitempty"`
	Description        string             `json:"description"`
	Context            Context            `json:"context"`
	Attachments        []ThreadAttachment `json:"attachments"`
	Disclosure         *PublicDisclosure  `json:"disclosure,omitempty"`
	AcceptedAt         string             `json:"acceptedAt"`
	PublishedAt        string             `json:"publishedAt,omitempty"`
	PublicationState   string             `json:"publicationState"`
	Reason             string             `json:"reason,omitempty"`
	QuestionID         string             `json:"questionId,omitempty"`
	QuestionRevision   int64              `json:"questionRevision,omitempty"`
	Outcome            *PublicOutcome     `json:"outcome,omitempty"`
}
type PublicThread struct {
	AssessmentDeliveryState  string               `json:"assessmentDeliveryState"`
	AssessmentDeliveryReason string               `json:"assessmentDeliveryReason"`
	SchemaVersion            int                  `json:"schemaVersion"`
	SubmissionID             string               `json:"submissionId"`
	Revision                 int64                `json:"revision"`
	Items                    []ThreadItem         `json:"items"`
	NextCursor               string               `json:"nextCursor"`
	WorkState                string               `json:"workState"`
	Summary                  string               `json:"summary"`
	WorkflowRevision         int64                `json:"workflowRevision"`
	ProjectionState          string               `json:"projectionState"`
	Question                 *ThreadQuestion      `json:"question,omitempty"`
	Outcome                  *PublicOutcome       `json:"outcome,omitempty"`
	DeliveryHistory          []PublicDeliveryFact `json:"deliveryHistory"`
	RemovalState             string               `json:"removalState"`
	CaseState                string               `json:"caseState"`
	ClosurePublicationState  string               `json:"closurePublicationState"`
	ClosedAt                 string               `json:"closedAt,omitempty"`
	ClosureReason            string               `json:"closureReason,omitempty"`
	Reason                   string               `json:"reason,omitempty"`
	AccessExpiresAt          string               `json:"accessExpiresAt"`
	ContentExpiresAt         string               `json:"contentExpiresAt"`
}

// CaseSnapshot contains verified public user content and intentional published
// official messages. Pending content is represented solely by observations;
// secrets and internal task/review logs never cross this boundary.
type CaseSnapshot struct {
	CaseID               string
	SourceRevision       int64
	InputRevision        int64
	IssueURL             string
	State                string
	Contributions        []CaseContribution
	Replies              []CaseReplyObservation
	QuestionPublication  *CaseQuestionPublication
	LatestProjection     *CaseProjectionObservation
	RevocationRevision   int64
	PublishedProjections []CasePublicProjection
	DeliveryHistory      []PublicDeliveryFact
}
type CasePublicProjection struct {
	ID                    string
	WorkflowRevision      int64
	ExpectedInputRevision int64
	WorkState             string
	Summary               string
	Question              *ProjectionQuestion
	Outcome               *PublicOutcome
	PublishedAt           time.Time
}
type CaseProjectionObservation struct {
	ID                    string
	WorkflowRevision      int64
	ExpectedInputRevision int64
	PublicationState      string
}
type CaseContribution struct {
	ID             string
	Revision       int64
	Digest         string
	Origin         string
	PolicyRevision string
	Provenance     string
	ReceivedAt     time.Time
	PublishedAt    time.Time
	Text           string
	Category       string
	Description    string
	Context        Context
	Attachments    []CaseAttachment
}
type CaseAttachment struct{ URL, SHA256, MediaType string }
type CaseReplyObservation struct {
	ID, QuestionID   string
	QuestionRevision int64
	ReceivedAt       time.Time
	PublicationState string
}
type CaseQuestionPublication struct {
	ID          string
	Revision    int64
	PublishedAt time.Time
}

type publicContribution struct {
	ID              string        `json:"id"`
	Sequence        int64         `json:"sequence"`
	Kind            string        `json:"kind"`
	Digest          string        `json:"digest"`
	Receipt         PublicReceipt `json:"receipt"`
	CommentID       int64         `json:"commentId,omitempty"`
	CommentNodeID   string        `json:"commentNodeId,omitempty"`
	CreateUncertain bool          `json:"createUncertain,omitempty"`
	AssetsVisible   bool          `json:"assetsVisible,omitempty"`
	Removed         bool          `json:"removed,omitempty"`
	Attempts        int           `json:"attempts"`
	NextAttempt     time.Time     `json:"nextAttempt,omitempty"`
}
type publicContributionPayload struct {
	Reply      *PublicSubmission  `json:"reply,omitempty"`
	Projection *ProjectionRequest `json:"projection,omitempty"`
}
