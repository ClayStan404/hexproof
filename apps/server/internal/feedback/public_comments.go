// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"context"
	"encoding/json"
	"strconv"
	"strings"
)

type githubComment struct {
	ID       int64  `json:"id"`
	NodeID   string `json:"node_id"`
	HTMLURL  string `json:"html_url"`
	IssueURL string `json:"issue_url"`
	Body     string `json:"body"`
	User     struct {
		ID int64 `json:"id"`
	} `json:"user"`
}

func (p *GitHubPublisher) commentBody(job PublicJob) string {
	c, payload := job.Contribution, job.Payload
	var body string
	if payload.Reply != nil {
		sub := payload.Reply
		m := sub.Manifest
		contextRaw, _ := json.MarshalIndent(m.Context, "", "  ")
		body = "Public follow-up submitted from Hexproof.\n\nSubmitted at: " + m.CreatedAt + "\n\n## Description\n\n" + publicFence(m.Description) + "\n\n## Technical context\n\n" + publicFence(string(contextRaw)) + "\n\n## Attachments\n\n"
		if m.QuestionID != "" {
			body += "Question: `" + m.QuestionID + "` revision " + strconv.FormatInt(m.QuestionRevision, 10) + ".\n"
		}
		for _, a := range m.Attachments {
			body += "- [" + a.ID + "](" + contributionAssetURL(sub.Target.PublicURL, job.ID, true, c.ID, a) + ") (" + a.Kind + ", " + a.MediaType + ", " + strconv.FormatInt(a.ByteLength, 10) + " bytes, SHA-256 `" + a.SHA256 + "`)\n"
		}
		descriptors, _ := json.MarshalIndent(m.Attachments, "", "  ")
		body += "\nAttachment descriptors:\n\n" + publicFence(string(descriptors)) + "\n"
		body += "\nDisclosure: `" + m.Disclosure.Revision + "`; provider policy: `" + m.Disclosure.ProviderPolicyRevision + "`; disclosure SHA-256: `" + m.Disclosure.SHA256 + "`.\n"
	} else {
		v := payload.Projection
		heading := "Official Hexproof assessment."
		if deliveryState(v.WorkState) {
			heading = "Official Hexproof delivery update."
		}
		body = heading + "\n\nWorkflow revision: " + strconv.FormatInt(v.WorkflowRevision, 10) + ".\n\nState: `" + v.WorkState + "`.\n\n" + publicFence(v.Summary) + "\n"
		if q := v.Question; q != nil {
			body += "\n## Follow-up question\n\n" + publicFence(q.Description) + "\n\nQuestion: `" + q.ID + "` revision " + strconv.FormatInt(q.Revision, 10) + "; code `" + q.Code + "`; reply window " + strconv.Itoa(q.TimeoutSeconds) + " seconds after verified publication.\n"
		}
		body += publicOutcomeText(v.Outcome)
	}
	return body + "\n<!-- hexproof-public-contribution-v2 " + job.ID + " " + c.ID + " " + c.Digest + " -->\n"
}
func (p *GitHubPublisher) ownedComment(c githubComment, job PublicJob) bool {
	return c.ID > 0 && c.NodeID != "" && len(c.NodeID) <= 256 && c.User.ID == p.config.PublisherActorID && c.Body == p.commentBody(job) && c.HTMLURL == "https://github.com/"+p.config.Repository+"/issues/"+strconv.Itoa(job.Record.IssueNumber)+"#issuecomment-"+strconv.FormatInt(c.ID, 10) && c.IssueURL == "https://api.github.com/repos/"+p.config.Repository+"/issues/"+strconv.Itoa(job.Record.IssueNumber)
}
func mappedComment(c githubComment) PublicResult {
	return PublicResult{Outcome: "mapped", CommentID: c.ID, CommentNodeID: c.NodeID}
}
func (p *GitHubPublisher) verifyParent(ctx context.Context, job PublicJob) PublicResult {
	path := p.apiBase + "/repos/" + p.config.Repository + "/issues/" + strconv.Itoa(job.Record.IssueNumber)
	status, raw, err := p.request(ctx, "GET", path, nil, true, 128<<10)
	if err != nil || status != 200 {
		return retryPublic("parent_publication_unavailable", err)
	}
	var issue githubIssue
	if json.Unmarshal(raw, &issue) != nil || !p.owned(issue, job.Record) || issue.NodeID != job.Record.IssueNodeID {
		return PublicResult{Outcome: "stalled", Code: "parent_projection_changed"}
	}
	return PublicResult{Outcome: "verified"}
}
func (p *GitHubPublisher) publishComment(ctx context.Context, job PublicJob) PublicResult {
	if job.Contribution == nil || job.Payload == nil {
		return PublicResult{Outcome: "stalled", Code: "invalid_contribution"}
	}
	if sub := job.Payload.Reply; sub != nil {
		if sub.Target != job.Record.Submission.Target {
			return PublicResult{Outcome: "stalled", Code: "publication_target_changed"}
		}
		d := sub.Manifest.Disclosure
		if job.Record.Receipt.RemovalState == "none" && (d.Revision != p.config.NoticeRevision || d.SHA256 != hashBytes([]byte(p.config.NoticeText)) || d.ProviderPolicyRevision != p.config.ProviderPolicyRevision) {
			return PublicResult{Outcome: "stalled", Code: "disclosure_changed"}
		}
	} else if job.Record.Receipt.RemovalState == "none" && job.Action == "comment-create" && job.Payload.Projection.ExpectedInputRevision != job.Record.InputRevision {
		return PublicResult{Outcome: "stalled", Code: "assessment_context_changed"}
	}
	path := p.apiBase + "/repos/" + p.config.Repository + "/issues"
	if job.Action == "comment-remove" {
		return p.removeComment(ctx, job, path)
	}
	if job.Record.Receipt.RemovalState != "none" && job.Action == "comment-reconcile" {
		issueURL := path + "/" + strconv.Itoa(job.Record.IssueNumber)
		status, _, err := p.request(ctx, "GET", issueURL, nil, true, 128<<10)
		if err == nil && (status == 404 || status == 410) {
			return p.verifyRemoved(ctx, issueURL)
		}
	}
	if result := p.verifyParent(ctx, job); result.Outcome != "verified" {
		return result
	}
	comments := path + "/" + strconv.Itoa(job.Record.IssueNumber) + "/comments"
	switch job.Action {
	case "comment-create":
		if result := p.verifyProjectionOutcome(ctx, job); result.Outcome != "verified" {
			return result
		}
		status, raw, err := p.request(ctx, "POST", comments, map[string]string{"body": p.commentBody(job)}, true, 128<<10)
		if status == 429 || status == 403 && isPublicRetry(err) {
			return retryPublic("publisher_rate_limited", err)
		}
		if err != nil || status == 0 || status >= 500 {
			v := retryPublic("comment_creation_uncertain", err)
			v.Outcome = "uncertain"
			return v
		}
		if status != 201 {
			return PublicResult{Outcome: "stalled", Code: "publisher_rejected_request"}
		}
		var c githubComment
		if json.Unmarshal(raw, &c) != nil || !p.ownedComment(c, job) {
			return PublicResult{Outcome: "uncertain", Code: "comment_provenance_unresolved"}
		}
		return mappedComment(c)
	case "comment-reconcile":
		var found *githubComment
		for page := 1; page <= 5; page++ {
			status, raw, err := p.request(ctx, "GET", comments+"?per_page=100&page="+strconv.Itoa(page), nil, true, 8<<20)
			if err != nil || status != 200 {
				return retryPublic("comment_reconciliation_unavailable", err)
			}
			var list []githubComment
			if json.Unmarshal(raw, &list) != nil {
				return retryPublic("comment_reconciliation_unavailable", nil)
			}
			for _, c := range list {
				if p.ownedComment(c, job) {
					if found != nil {
						return PublicResult{Outcome: "stalled", Code: "multiple_comment_matches"}
					}
					copy := c
					found = &copy
				}
			}
			if len(list) < 100 {
				break
			}
		}
		if found != nil {
			return mappedComment(*found)
		}
		return PublicResult{Outcome: "retry", Code: "comment_creation_uncertain"}
	case "comment-verify":
		if result := p.verifyProjectionOutcome(ctx, job); result.Outcome != "verified" {
			return result
		}
		url := path + "/comments/" + strconv.FormatInt(job.Contribution.CommentID, 10)
		for _, auth := range []bool{true, false} {
			status, raw, err := p.request(ctx, "GET", url, nil, auth, 128<<10)
			if err != nil || status != 200 {
				return retryPublic("comment_verification_unavailable", err)
			}
			var c githubComment
			if json.Unmarshal(raw, &c) != nil || !p.ownedComment(c, job) || c.NodeID != job.Contribution.CommentNodeID {
				return PublicResult{Outcome: "stalled", Code: "comment_projection_changed"}
			}
		}
		if sub := job.Payload.Reply; sub != nil {
			for _, a := range sub.Manifest.Attachments {
				status, raw, err := p.request(ctx, "GET", contributionAssetURL(sub.Target.PublicURL, job.ID, true, sub.Manifest.SubmissionID, a), nil, false, a.ByteLength)
				if err != nil || status != 200 || int64(len(raw)) != a.ByteLength || hashBytes(raw) != a.SHA256 {
					return retryPublic("public_attachment_unavailable", err)
				}
			}
		}
		return PublicResult{Outcome: "verified"}
	}
	return PublicResult{Outcome: "stalled", Code: "invalid_comment_action"}
}
func (p *GitHubPublisher) removeComment(ctx context.Context, job PublicJob, path string) PublicResult {
	issueURL := path + "/" + strconv.Itoa(job.Record.IssueNumber)
	url := path + "/comments/" + strconv.FormatInt(job.Contribution.CommentID, 10)
	status, raw, err := p.request(ctx, "GET", issueURL, nil, true, 128<<10)
	if err != nil {
		return retryPublic("removal_verification_unavailable", err)
	}
	if status != 404 && status != 410 {
		var issue githubIssue
		if status != 200 || json.Unmarshal(raw, &issue) != nil || !p.owned(issue, job.Record) || issue.NodeID != job.Record.IssueNodeID {
			return PublicResult{Outcome: "stalled", Code: "removal_requires_moderation"}
		}
		status, _, err = p.request(ctx, "PUT", issueURL+"/lock", map[string]string{"lock_reason": "resolved"}, true, 128<<10)
		if err != nil || status != 204 {
			return PublicResult{Outcome: "stalled", Code: "removal_lock_unavailable"}
		}
		if result := p.verifyParent(ctx, job); result.Outcome != "verified" {
			return result
		}
	}
	if err = p.repository(ctx); err != nil {
		return retryPublic("removal_verification_unavailable", err)
	}
	status, raw, err = p.request(ctx, "GET", url, nil, true, 128<<10)
	if err != nil {
		return retryPublic("comment_removal_unavailable", err)
	}
	if status != 404 && status != 410 {
		var c githubComment
		if status != 200 || json.Unmarshal(raw, &c) != nil || !p.ownedComment(c, job) || c.NodeID != job.Contribution.CommentNodeID {
			return PublicResult{Outcome: "stalled", Code: "comment_removal_requires_moderation"}
		}
		status, _, err = p.request(ctx, "DELETE", url, nil, true, 128<<10)
		if err != nil || status != 204 && status != 404 && status != 410 {
			return retryPublic("comment_removal_uncertain", err)
		}
	}
	if err = p.repository(ctx); err != nil {
		return retryPublic("comment_removal_verification_unavailable", err)
	}
	for _, auth := range []bool{true, false} {
		status, _, err = p.request(ctx, "GET", url, nil, auth, 128<<10)
		if err != nil || status != 404 && status != 410 {
			return retryPublic("comment_removal_verification_unavailable", err)
		}
	}
	return PublicResult{Outcome: "removed"}
}

func isCommentAction(action string) bool { return strings.HasPrefix(action, "comment-") }
