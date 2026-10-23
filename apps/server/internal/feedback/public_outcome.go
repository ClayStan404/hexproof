// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"regexp"
	"strconv"
)

var publicCommitPattern = regexp.MustCompile(`^[0-9a-f]{40}$`)
var publicReleaseVersionPattern = regexp.MustCompile(`^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$`)

func validProjectionOutcome(p ProjectionRequest, repository string, ownIssue int) bool {
	if p.Outcome == nil {
		return !oneOf(p.WorkState, "duplicate", "source-published-awaiting-release", "released")
	}
	o := p.Outcome
	if o.Repository != repository || p.Question != nil {
		return false
	}
	switch o.Kind {
	case "duplicate":
		return p.WorkState == "duplicate" && o.IssueNumber > 0 && o.IssueNumber <= 2147483647 && o.IssueNumber != ownIssue && o.Commit == "" && o.Tag == "" && o.Version == ""
	case "source":
		return p.WorkState == "source-published-awaiting-release" && o.IssueNumber == 0 && publicCommitPattern.MatchString(o.Commit) && o.Tag == "" && o.Version == ""
	case "release":
		return p.WorkState == "released" && o.IssueNumber == 0 && publicCommitPattern.MatchString(o.Commit) && publicReleaseVersionPattern.MatchString(o.Version) && o.Tag == "v"+o.Version
	}
	return false
}

func appendDeliveryFact(history []PublicDeliveryFact, p ProjectionRequest, publishedAt string) []PublicDeliveryFact {
	// Old persisted prose-only delivery projections remain readable, but cannot
	// become verified delivery facts by inference during an upgrade.
	if p.Outcome != nil && oneOf(p.Outcome.Kind, "source", "release") {
		history = append(history, PublicDeliveryFact{ProjectionID: p.ID, InputRevision: p.ExpectedInputRevision, WorkflowRevision: p.WorkflowRevision, PublishedAt: publishedAt, Outcome: *p.Outcome})
	}
	return history
}

func publicOutcomeText(o *PublicOutcome) string {
	if o == nil {
		return ""
	}
	base := "https://github.com/" + o.Repository
	switch o.Kind {
	case "duplicate":
		return "\nRelated public report: " + base + "/issues/" + strconv.Itoa(o.IssueNumber) + ".\n"
	case "source":
		return "\nPublished source: " + base + "/commit/" + o.Commit + ". Awaiting release.\n"
	case "release":
		return "\nReleased version: `" + o.Version + "` (" + base + "/releases/tag/" + o.Tag + "). Includes public change " + base + "/commit/" + o.Commit + ".\n"
	}
	return ""
}
