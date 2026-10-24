// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

// GitHubPublisher never follows redirects or accepts a configurable credential
// destination. Tests replace its private endpoints with isolated fake servers.
type GitHubPublisher struct {
	config     PublicConfig
	publicURL  string
	apiBase    string
	graphqlURL string
	http       *http.Client
	token      string
}

func NewGitHubPublisher(c PublicConfig, publicURL string) (*GitHubPublisher, error) {
	info, err := os.Lstat(c.TokenFile)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0 || info.Size() > 4096 {
		return nil, fmt.Errorf("public publisher credential unavailable")
	}
	raw, err := os.ReadFile(c.TokenFile)
	if err != nil {
		return nil, fmt.Errorf("public publisher credential unavailable")
	}
	token := strings.TrimSpace(string(raw))
	if token == "" || strings.ContainsAny(token, "\r\n\t ") {
		return nil, fmt.Errorf("invalid public publisher credential")
	}
	c.PublicURL = publicURL
	return &GitHubPublisher{config: c, publicURL: publicURL, apiBase: "https://api.github.com", graphqlURL: "https://api.github.com/graphql", token: token, http: &http.Client{Timeout: 25 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}, nil
}

type githubIssue struct {
	Number   int    `json:"number"`
	NodeID   string `json:"node_id"`
	HTMLURL  string `json:"html_url"`
	Body     string `json:"body"`
	Title    string `json:"title"`
	Comments int    `json:"comments"`
	State    string `json:"state"`
	User     struct {
		ID int64 `json:"id"`
	} `json:"user"`
	PullRequest json.RawMessage `json:"pull_request"`
}

func (p *GitHubPublisher) request(ctx context.Context, method, url string, input any, auth bool, limit int64) (int, []byte, error) {
	var body io.Reader
	if input != nil {
		raw, err := json.Marshal(input)
		if err != nil {
			return 0, nil, err
		}
		body = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, method, url, body)
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2026-03-10")
	req.Header.Set("User-Agent", "Hexproof-Public-Feedback")
	if input != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if auth {
		req.Header.Set("Authorization", "Bearer "+p.token)
	}
	response, err := p.http.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer response.Body.Close()
	raw, err := readBounded(response.Body, limit)
	if err == nil && (response.StatusCode == 429 || response.StatusCode == 503 || response.StatusCode == 403 && (response.Header.Get("Retry-After") != "" || response.Header.Get("X-RateLimit-Remaining") == "0")) {
		delay := 2 * time.Minute
		if n, e := strconv.Atoi(response.Header.Get("Retry-After")); e == nil && n > 0 {
			delay = time.Duration(min(n, 21600)) * time.Second
		} else if at, e := http.ParseTime(response.Header.Get("Retry-After")); e == nil {
			delay = time.Until(at)
		}
		if reset, e := strconv.ParseInt(response.Header.Get("X-RateLimit-Reset"), 10, 64); e == nil {
			delay = max(delay, time.Until(time.Unix(reset, 0)))
		}
		err = &publicRetryError{delay: max(time.Second, min(delay, 6*time.Hour))}
	}
	return response.StatusCode, raw, err
}
func (p *GitHubPublisher) repository(ctx context.Context) error {
	status, raw, err := p.request(ctx, "GET", p.apiBase+"/repos/"+p.config.Repository, nil, true, 128<<10)
	var repo struct {
		ID        int64  `json:"id"`
		FullName  string `json:"full_name"`
		Private   bool   `json:"private"`
		HasIssues bool   `json:"has_issues"`
	}
	if err != nil {
		return err
	}
	if status != 200 || json.Unmarshal(raw, &repo) != nil || repo.ID != p.config.RepositoryID || repo.FullName != p.config.Repository || repo.Private || !repo.HasIssues {
		return ErrUnavailable
	}
	return nil
}
func legacyIssueTitle(r PublicRecord) string {
	return "[Client feedback: " + r.Submission.Manifest.Category + "] " + r.Receipt.SubmissionID
}
func publicFence(text string) string {
	n := 3
	for strings.Contains(text, strings.Repeat("`", n)) {
		n++
	}
	fence := strings.Repeat("`", n)
	return fence + "text\n" + text + "\n" + fence
}

// Keep the original projection byte-for-byte so existing publications can still
// be reconciled, verified, closed and removed after a renderer upgrade.
func (p *GitHubPublisher) legacyIssueBody(r PublicRecord) string {
	m := r.Submission.Manifest
	contextRaw, _ := json.MarshalIndent(m.Context, "", "  ")
	body := "Public feedback submitted from Hexproof. Development assessment has not started.\n\nSubmitted at: " + m.CreatedAt + "\n\n## Description\n\n" + publicFence(m.Description) + "\n\n## Technical context\n\n" + publicFence(string(contextRaw)) + "\n\n## Attachments\n\n"
	if len(m.Attachments) == 0 {
		body += "None.\n"
	}
	for _, a := range m.Attachments {
		body += "- [" + a.ID + "](" + p.assetURL(r.Receipt.SubmissionID, a) + ") (" + a.Kind + ", " + a.MediaType + ", " + strconv.FormatInt(a.ByteLength, 10) + " bytes, SHA-256 `" + a.SHA256 + "`)\n"
	}
	descriptors, _ := json.MarshalIndent(m.Attachments, "", "  ")
	body += "\nAttachment descriptors:\n\n" + publicFence(string(descriptors)) + "\n"
	body += "\nDisclosure: `" + m.Disclosure.Revision + "`; provider policy: `" + m.Disclosure.ProviderPolicyRevision + "`; disclosure SHA-256: `" + m.Disclosure.SHA256 + "`.\n"
	body += "\n<!-- hexproof-public-v2 " + m.SubmissionID + " " + r.Digest + " -->\n"
	return body
}
func (p *GitHubPublisher) assetURL(id string, a Attachment) string {
	return p.publicURL + "/assets/" + id + "/" + a.ID + "/" + a.SHA256
}
func (p *GitHubPublisher) owned(issue githubIssue, r PublicRecord) bool {
	if issue.Number <= 0 || issue.NodeID == "" || len(issue.NodeID) > 256 || issue.HTMLURL != "https://github.com/"+p.config.Repository+"/issues/"+strconv.Itoa(issue.Number) || (len(issue.PullRequest) != 0 && string(issue.PullRequest) != "null") || issue.User.ID != p.config.PublisherActorID {
		return false
	}
	// Accept only complete, exact projections. A copied marker or a mixture of
	// old and new fields is not enough to establish publication ownership.
	return issue.Title == issueTitle(r) && issue.Body == p.issueBody(r) ||
		issue.Title == legacyIssueTitle(r) && issue.Body == p.legacyIssueBody(r)
}
func mappedResult(issue githubIssue) PublicResult {
	return PublicResult{Outcome: "mapped", IssueNumber: issue.Number, IssueNodeID: issue.NodeID, IssueURL: issue.HTMLURL}
}
func (p *GitHubPublisher) Publish(ctx context.Context, job PublicJob) PublicResult {
	ctx, cancel := context.WithTimeout(ctx, 90*time.Second)
	defer cancel()
	if job.Record.Submission == nil || job.Record.Submission.Target != p.config.target() || p.publicURL != job.Record.Submission.Target.PublicURL {
		return PublicResult{Outcome: "stalled", Code: "publication_target_changed"}
	}
	disclosure := job.Record.Submission.Manifest.Disclosure
	if job.Record.Receipt.RemovalState == "none" && job.Action != "close" && !isCommentAction(job.Action) && (disclosure.Revision != p.config.NoticeRevision || disclosure.SHA256 != hashBytes([]byte(p.config.NoticeText)) || disclosure.ProviderPolicyRevision != p.config.ProviderPolicyRevision) {
		return PublicResult{Outcome: "stalled", Code: "disclosure_changed"}
	}
	if err := p.repository(ctx); err != nil {
		return retryPublic("repository_unavailable", err)
	}
	if isCommentAction(job.Action) {
		return p.publishComment(ctx, job)
	}
	path := p.apiBase + "/repos/" + p.config.Repository + "/issues"
	switch job.Action {
	case "create":
		status, raw, err := p.request(ctx, "POST", path, map[string]string{"title": issueTitle(job.Record), "body": p.issueBody(job.Record)}, true, 128<<10)
		if status == 429 || status == 403 && isPublicRetry(err) {
			return retryPublic("publisher_rate_limited", err)
		}
		if err != nil || status == 0 || status >= 500 {
			result := retryPublic("creation_uncertain", err)
			result.Outcome = "uncertain"
			return result
		}
		if status != 201 {
			return PublicResult{Outcome: "stalled", Code: "publisher_rejected_request"}
		}
		var issue githubIssue
		if json.Unmarshal(raw, &issue) != nil || !p.owned(issue, job.Record) {
			return PublicResult{Outcome: "uncertain", Code: "publisher_provenance_unresolved"}
		}
		return mappedResult(issue)
	case "reconcile":
		var found *githubIssue
		for page := 1; page <= 5; page++ {
			status, raw, err := p.request(ctx, "GET", path+"?state=all&sort=created&direction=desc&per_page=100&page="+strconv.Itoa(page), nil, true, 8<<20)
			if err != nil || status != 200 {
				return retryPublic("reconciliation_unavailable", err)
			}
			var issues []githubIssue
			if json.Unmarshal(raw, &issues) != nil {
				return retryPublic("reconciliation_unavailable", err)
			}
			for _, issue := range issues {
				if p.owned(issue, job.Record) {
					if found != nil {
						return PublicResult{Outcome: "stalled", Code: "multiple_publication_matches"}
					}
					copy := issue
					found = &copy
				}
			}
			if len(issues) < 100 {
				break
			}
		}
		if found != nil {
			return mappedResult(*found)
		}
		// GitHub listing/search has no authoritative absence guarantee after an
		// ambiguous write. An empty result never grants a second creation attempt.
		return PublicResult{Outcome: "retry", Code: "creation_uncertain"}
	case "verify":
		status, raw, err := p.request(ctx, "GET", path+"/"+strconv.Itoa(job.Record.IssueNumber), nil, true, 128<<10)
		var issue githubIssue
		if err != nil || status != 200 {
			return retryPublic("publication_verification_unavailable", err)
		}
		if json.Unmarshal(raw, &issue) != nil || !p.owned(issue, job.Record) || issue.NodeID != job.Record.IssueNodeID {
			return PublicResult{Outcome: "stalled", Code: "public_projection_changed"}
		}
		// Verify public access with no publisher credentials as well.
		status, raw, err = p.request(ctx, "GET", path+"/"+strconv.Itoa(issue.Number), nil, false, 128<<10)
		var publicIssue githubIssue
		if err != nil || status != 200 || json.Unmarshal(raw, &publicIssue) != nil || !p.owned(publicIssue, job.Record) {
			return PublicResult{Outcome: "retry", Code: "public_issue_unavailable"}
		}
		for _, a := range job.Record.Submission.Manifest.Attachments {
			status, raw, err = p.request(ctx, "GET", p.assetURL(job.ID, a), nil, false, a.ByteLength)
			if err != nil || status != 200 || int64(len(raw)) != a.ByteLength || hashBytes(raw) != a.SHA256 {
				return retryPublic("public_attachment_unavailable", err)
			}
		}
		result := mappedResult(issue)
		result.Outcome = "verified"
		return result
	case "remove":
		return p.remove(ctx, job, path)
	case "close":
		return p.closeIssue(ctx, job, path)
	default:
		return PublicResult{Outcome: "stalled", Code: "invalid_publication_action"}
	}
}
func (p *GitHubPublisher) remove(ctx context.Context, job PublicJob, path string) PublicResult {
	issueURL := path + "/" + strconv.Itoa(job.Record.IssueNumber)
	// Lock before checking comments. Ordinary contributors cannot race a new
	// comment into deletion; privileged writers must honor the same lock.
	status, raw, err := p.request(ctx, "GET", issueURL, nil, true, 128<<10)
	if err == nil && (status == 404 || status == 410) {
		return p.verifyRemoved(ctx, issueURL)
	}
	var beforeLock githubIssue
	if err != nil || status != 200 || json.Unmarshal(raw, &beforeLock) != nil {
		return retryPublic("removal_verification_unavailable", err)
	}
	if !p.owned(beforeLock, job.Record) || beforeLock.NodeID != job.Record.IssueNodeID {
		return PublicResult{Outcome: "stalled", Code: "removal_requires_moderation"}
	}
	status, _, err = p.request(ctx, "PUT", issueURL+"/lock", map[string]string{"lock_reason": "resolved"}, true, 128<<10)
	if err != nil || status != 204 {
		return PublicResult{Outcome: "stalled", Code: "removal_lock_unavailable"}
	}
	if err := p.repository(ctx); err != nil {
		return retryPublic("removal_verification_unavailable", err)
	}
	status, raw, err = p.request(ctx, "GET", issueURL, nil, true, 128<<10)
	if err != nil {
		return PublicResult{Outcome: "retry", Code: "removal_verification_unavailable"}
	}
	if status == 404 || status == 410 {
		return p.verifyRemoved(ctx, issueURL)
	}
	var issue githubIssue
	if status != 200 || json.Unmarshal(raw, &issue) != nil {
		return PublicResult{Outcome: "retry", Code: "removal_verification_unavailable"}
	}
	if !p.owned(issue, job.Record) || issue.NodeID != job.Record.IssueNodeID || issue.Comments != 0 {
		return PublicResult{Outcome: "stalled", Code: "removal_requires_moderation"}
	}
	input := map[string]any{"query": "mutation($input: DeleteIssueInput!) { deleteIssue(input: $input) { clientMutationId } }", "variables": map[string]any{"input": map[string]string{"issueId": issue.NodeID, "clientMutationId": job.ID}}}
	status, raw, err = p.request(ctx, "POST", p.graphqlURL, input, true, 128<<10)
	var response struct {
		Data struct {
			DeleteIssue *struct {
				ClientMutationID string `json:"clientMutationId"`
			} `json:"deleteIssue"`
		} `json:"data"`
		Errors []json.RawMessage `json:"errors"`
	}
	if err != nil || status != 200 {
		return retryPublic("removal_uncertain", err)
	}
	if json.Unmarshal(raw, &response) != nil || len(response.Errors) > 0 || response.Data.DeleteIssue == nil || response.Data.DeleteIssue.ClientMutationID != job.ID {
		return PublicResult{Outcome: "stalled", Code: "removal_permission_unavailable"}
	}
	return p.verifyRemoved(ctx, issueURL)
}
func (p *GitHubPublisher) verifyRemoved(ctx context.Context, issueURL string) PublicResult {
	// Revalidate repository access to distinguish deletion from credential loss.
	if err := p.repository(ctx); err != nil {
		return retryPublic("removal_verification_unavailable", err)
	}
	for _, auth := range []bool{true, false} {
		status, _, err := p.request(ctx, "GET", issueURL, nil, auth, 128<<10)
		if err != nil || (status != 404 && status != 410) {
			return PublicResult{Outcome: "retry", Code: "removal_verification_unavailable"}
		}
	}
	return PublicResult{Outcome: "removed"}
}
func RunPublicOutbox(ctx context.Context, s *PublicStore, publisher PublicPublisher) {
	for ctx.Err() == nil {
		job, err := s.Claim()
		if err == nil && job != nil {
			result := publisher.Publish(ctx, *job)
			if err := s.Finish(*job, result); err != nil {
				log.Print("public feedback outbox persistence unavailable")
			}
			continue
		}
		if err != nil {
			log.Print("public feedback outbox unavailable")
		}
		timer := time.NewTimer(time.Second)
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.C:
		}
	}
}

type publicRetryError struct{ delay time.Duration }

func (e *publicRetryError) Error() string { return "publisher_temporarily_unavailable" }
func isPublicRetry(err error) bool        { var r *publicRetryError; return errors.As(err, &r) }
func retryPublic(code string, err error) PublicResult {
	result := PublicResult{Outcome: "retry", Code: code}
	var r *publicRetryError
	if errors.As(err, &r) {
		result.RetryAfter = r.delay
	}
	return result
}
