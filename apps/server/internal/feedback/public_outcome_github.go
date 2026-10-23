// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"context"
	"encoding/json"
	"strconv"
	"time"
)

func invalidPublicOutcome() PublicResult {
	return PublicResult{Outcome: "stalled", Code: "public_outcome_unverified"}
}

// outcomeJSON is read-only and accepts only paths assembled from validated
// fields and the fixed repository. No URL supplied by an agent is requested.
func (p *GitHubPublisher) outcomeJSON(ctx context.Context, path string, auth bool, value any) PublicResult {
	status, raw, err := p.request(ctx, "GET", p.apiBase+"/repos/"+p.config.Repository+path, nil, auth, 2<<20)
	if err != nil || status == 0 || status >= 500 {
		return retryPublic("public_outcome_unavailable", err)
	}
	if status != 200 || json.Unmarshal(raw, value) != nil {
		return invalidPublicOutcome()
	}
	return PublicResult{Outcome: "verified"}
}

func (p *GitHubPublisher) verifyProjectionOutcome(ctx context.Context, job PublicJob) PublicResult {
	projection := job.Payload.Projection
	if projection == nil || projection.Outcome == nil {
		// Compatibility: already admitted legacy prose-only projections keep
		// their original reconciliation path; new admission requires outcomes.
		return PublicResult{Outcome: "verified"}
	}
	if !validProjectionOutcome(*projection, p.config.Repository, job.Record.IssueNumber) {
		return invalidPublicOutcome()
	}
	o := projection.Outcome
	var tagCommit string
	for _, auth := range []bool{true, false} {
		var repo struct {
			ID       int64  `json:"id"`
			FullName string `json:"full_name"`
			Private  bool   `json:"private"`
		}
		if result := p.outcomeJSON(ctx, "", auth, &repo); result.Outcome != "verified" {
			return result
		}
		if repo.ID != p.config.RepositoryID || repo.FullName != p.config.Repository || repo.Private {
			return invalidPublicOutcome()
		}
		if o.Kind == "duplicate" {
			var issue githubIssue
			if result := p.outcomeJSON(ctx, "/issues/"+strconv.Itoa(o.IssueNumber), auth, &issue); result.Outcome != "verified" {
				return result
			}
			if issue.Number != o.IssueNumber || issue.HTMLURL != "https://github.com/"+o.Repository+"/issues/"+strconv.Itoa(o.IssueNumber) || (len(issue.PullRequest) != 0 && string(issue.PullRequest) != "null") {
				return invalidPublicOutcome()
			}
			continue
		}
		var commit struct {
			SHA     string `json:"sha"`
			HTMLURL string `json:"html_url"`
		}
		if result := p.outcomeJSON(ctx, "/commits/"+o.Commit, auth, &commit); result.Outcome != "verified" {
			return result
		}
		if commit.SHA != o.Commit || commit.HTMLURL != "https://github.com/"+o.Repository+"/commit/"+o.Commit {
			return invalidPublicOutcome()
		}
		if o.Kind == "source" {
			continue
		}
		var release struct {
			ID          int64  `json:"id"`
			Tag         string `json:"tag_name"`
			HTMLURL     string `json:"html_url"`
			Draft       bool   `json:"draft"`
			Prerelease  bool   `json:"prerelease"`
			PublishedAt string `json:"published_at"`
		}
		if result := p.outcomeJSON(ctx, "/releases/tags/"+o.Tag, auth, &release); result.Outcome != "verified" {
			return result
		}
		publishedAt, err := time.Parse(time.RFC3339, release.PublishedAt)
		if err != nil || publishedAt.IsZero() || release.ID <= 0 || release.Tag != o.Tag || release.Draft || release.Prerelease || release.HTMLURL != "https://github.com/"+o.Repository+"/releases/tag/"+o.Tag {
			return invalidPublicOutcome()
		}
		resolved, result := p.releaseTagCommit(ctx, o.Tag, auth)
		if result.Outcome != "verified" {
			return result
		}
		if tagCommit != "" && resolved != tagCommit {
			return invalidPublicOutcome()
		}
		tagCommit = resolved
		if resolved != o.Commit {
			var comparison struct {
				Status string `json:"status"`
				Base   struct {
					SHA string `json:"sha"`
				} `json:"base_commit"`
				MergeBase struct {
					SHA string `json:"sha"`
				} `json:"merge_base_commit"`
			}
			if result := p.outcomeJSON(ctx, "/compare/"+o.Commit+"..."+resolved+"?per_page=1", auth, &comparison); result.Outcome != "verified" {
				return result
			}
			if comparison.Status != "ahead" || comparison.Base.SHA != o.Commit || comparison.MergeBase.SHA != o.Commit {
				return invalidPublicOutcome()
			}
		}
	}
	return PublicResult{Outcome: "verified"}
}

type githubGitObject struct {
	Type string `json:"type"`
	SHA  string `json:"sha"`
}

func (p *GitHubPublisher) releaseTagCommit(ctx context.Context, tag string, auth bool) (string, PublicResult) {
	var ref struct {
		Ref    string          `json:"ref"`
		Object githubGitObject `json:"object"`
	}
	if result := p.outcomeJSON(ctx, "/git/ref/tags/"+tag, auth, &ref); result.Outcome != "verified" {
		return "", result
	}
	if ref.Ref != "refs/tags/"+tag {
		return "", invalidPublicOutcome()
	}
	object := ref.Object
	seen := map[string]bool{}
	for depth := 0; depth < 5; depth++ {
		if !publicCommitPattern.MatchString(object.SHA) || seen[object.SHA] {
			return "", invalidPublicOutcome()
		}
		seen[object.SHA] = true
		if object.Type == "commit" {
			return object.SHA, PublicResult{Outcome: "verified"}
		}
		if object.Type != "tag" {
			return "", invalidPublicOutcome()
		}
		var annotation struct {
			SHA    string          `json:"sha"`
			Object githubGitObject `json:"object"`
		}
		if result := p.outcomeJSON(ctx, "/git/tags/"+object.SHA, auth, &annotation); result.Outcome != "verified" {
			return "", result
		}
		if annotation.SHA != object.SHA {
			return "", invalidPublicOutcome()
		}
		object = annotation.Object
	}
	return "", invalidPublicOutcome()
}
