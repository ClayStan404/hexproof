// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"context"
	"encoding/json"
	"strconv"
)

func (p *GitHubPublisher) closeIssue(ctx context.Context, job PublicJob, path string) PublicResult {
	if job.Record.Receipt.CaseState != "closed" || job.Record.Receipt.RemovalState != "none" || job.Record.IssueNumber < 1 || job.Record.IssueNodeID == "" {
		return PublicResult{Outcome: "stalled", Code: "invalid_closure_action"}
	}
	url := path + "/" + strconv.Itoa(job.Record.IssueNumber)
	status, raw, err := p.request(ctx, "GET", url, nil, true, 128<<10)
	if err != nil || status != 200 {
		return retryPublic("closure_verification_unavailable", err)
	}
	var issue githubIssue
	if json.Unmarshal(raw, &issue) != nil || !p.owned(issue, job.Record) || issue.NodeID != job.Record.IssueNodeID || issue.Number != job.Record.IssueNumber {
		return PublicResult{Outcome: "stalled", Code: "closure_projection_changed"}
	}
	if !oneOf(issue.State, "open", "closed") {
		return PublicResult{Outcome: "retry", Code: "closure_verification_unavailable"}
	}
	if issue.State == "open" {
		status, _, err = p.request(ctx, "PATCH", url, map[string]string{"state": "closed", "state_reason": "not_planned"}, true, 128<<10)
		if status == 429 || status == 403 && isPublicRetry(err) {
			return retryPublic("publisher_rate_limited", err)
		}
		if err == nil && status != 200 && status > 0 && status < 500 {
			return PublicResult{Outcome: "stalled", Code: "closure_permission_unavailable"}
		}
		// A lost PATCH response is reconciled by exact identity/state readback.
		// Repeating this action never creates an issue or changes its content.
	}
	if err := p.repository(ctx); err != nil {
		return retryPublic("closure_verification_unavailable", err)
	}
	for _, auth := range []bool{true, false} {
		status, raw, err = p.request(ctx, "GET", url, nil, auth, 128<<10)
		if err != nil || status != 200 {
			return retryPublic("closure_verification_unavailable", err)
		}
		var current githubIssue
		if json.Unmarshal(raw, &current) != nil || !p.owned(current, job.Record) || current.NodeID != job.Record.IssueNodeID || current.Number != job.Record.IssueNumber {
			return PublicResult{Outcome: "stalled", Code: "closure_projection_changed"}
		}
		if current.State != "closed" {
			return PublicResult{Outcome: "retry", Code: "closure_verification_unavailable"}
		}
	}
	return PublicResult{Outcome: "closed"}
}
