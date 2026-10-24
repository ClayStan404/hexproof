// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
)

func chineseIssue(r PublicRecord) bool {
	language := strings.ToLower(strings.ReplaceAll(r.Submission.Manifest.Context.UILanguage, "_", "-"))
	return language == "zh" || strings.HasPrefix(language, "zh-")
}

func issueText(chinese bool, zh, en string) string {
	if chinese {
		return zh
	}
	return en
}

func issueTitle(r PublicRecord) string {
	m := r.Submission.Manifest
	chinese := chineseIssue(r)
	category := issueText(chinese, "反馈", "Feedback")
	switch m.Category {
	case "problem":
		category = issueText(chinese, "问题", "Problem")
	case "suggestion":
		category = issueText(chinese, "建议", "Suggestion")
	}
	// Derive a deterministic excerpt from approved text, without another model
	// call or a guessed diagnosis. Keep the full description in the body.
	summary := ""
	for _, line := range strings.Split(strings.ReplaceAll(m.Description, "\r", "\n"), "\n") {
		if summary = strings.Join(strings.Fields(line), " "); summary != "" {
			break
		}
	}
	if summary == "" {
		summary = issueText(chinese, "客户端反馈", "Client feedback")
	}
	// Titles are single-line plain text. Break mentions, including in excerpts
	// that were previously only visible inside a non-notifying code fence.
	summary = strings.ReplaceAll(summary, "@", "@\u200b")
	title := []rune("[" + category + "] " + summary)
	const maxTitleRunes = 100
	if len(title) > maxTitleRunes {
		title = append(title[:maxTitleRunes-1], '…')
	}
	return string(title)
}

func issueAttachmentName(chinese bool, kind string, number int) string {
	name := issueText(chinese, "附件", "Attachment")
	switch kind {
	case "screenshot":
		name = issueText(chinese, "截图", "Screenshot")
	case "forge_crash":
		name = issueText(chinese, "崩溃报告", "Crash report")
	case "hosting_diagnostics":
		name = issueText(chinese, "托管诊断", "Hosting diagnostics")
	}
	return name + " " + strconv.Itoa(number)
}

func issueAttachmentSize(size int64) string {
	if size >= 1<<20 {
		return fmt.Sprintf("%.1f MiB", float64(size)/(1<<20))
	}
	if size >= 1<<10 {
		return fmt.Sprintf("%.1f KiB", float64(size)/(1<<10))
	}
	return strconv.FormatInt(size, 10) + " B"
}

func (p *GitHubPublisher) issueBody(r PublicRecord) string {
	m := r.Submission.Manifest
	chinese := chineseIssue(r)
	body := issueText(chinese,
		"来自 Hexproof 客户端的公开反馈。处理进展见下方回复。",
		"Public feedback from the Hexproof client. Follow-up and progress appear in the replies below.")
	body += "\n\n## " + issueText(chinese, "反馈内容", "Feedback") + "\n\n" + publicFence(m.Description) + "\n"
	var environment []string
	if m.Context.AppVersion != "" {
		environment = append(environment, "Hexproof `"+m.Context.AppVersion+"`")
	}
	if platform := strings.TrimSpace(m.Context.OSFamily + " " + m.Context.Architecture); platform != "" {
		environment = append(environment, "`"+platform+"`")
	}
	if m.Context.GameMode != "" {
		environment = append(environment, "`"+m.Context.GameMode+"`")
	}
	if len(environment) > 0 {
		body += "\n**" + issueText(chinese, "环境：", "Environment:") + "** " + strings.Join(environment, " · ") + "\n"
	}
	if len(m.Attachments) > 0 {
		body += "\n## " + issueText(chinese, "附件", "Attachments") + "\n\n"
		counts := make(map[string]int)
		for _, a := range m.Attachments {
			counts[a.Kind]++
			name := issueAttachmentName(chinese, a.Kind, counts[a.Kind])
			body += "- [" + name + "](" + p.assetURL(r.Receipt.SubmissionID, a) + ") (" + issueAttachmentSize(a.ByteLength) + ")\n"
		}
	}
	// Diagnostics and provenance remain available verbatim, without dominating
	// the reader's initial view or exposing credentials in new fields.
	body += "\n<details>\n<summary>" + issueText(chinese, "技术信息与追踪标识", "Technical details and tracking") + "</summary>\n\n"
	body += issueText(chinese, "提交时间", "Submitted at") + ": " + m.CreatedAt + "\n\n"
	body += issueText(chinese, "反馈编号", "Feedback ID") + ": `" + m.SubmissionID + "`\n\n"
	contextRaw, _ := json.MarshalIndent(m.Context, "", "  ")
	body += "### " + issueText(chinese, "技术信息", "Technical context") + "\n\n" + publicFence(string(contextRaw)) + "\n"
	if len(m.Attachments) > 0 {
		descriptors, _ := json.MarshalIndent(m.Attachments, "", "  ")
		body += "\n### " + issueText(chinese, "附件校验信息", "Attachment descriptors") + "\n\n" + publicFence(string(descriptors)) + "\n"
	}
	body += "\nDisclosure: `" + m.Disclosure.Revision + "`; provider policy: `" + m.Disclosure.ProviderPolicyRevision + "`; disclosure SHA-256: `" + m.Disclosure.SHA256 + "`.\n"
	body += "\n</details>\n\n<!-- hexproof-public-v2 " + m.SubmissionID + " " + r.Digest + " -->\n"
	return body
}
