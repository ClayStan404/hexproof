// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"encoding/json"
	"strings"
	"testing"
	"unicode/utf8"
)

func TestPublicIssueReadableTitles(t *testing.T) {
	for _, test := range []struct {
		name, language, category, description, want string
	}{
		{"Chinese problem", "zh", "problem", "交互界面遮挡战场右下角的永久物", "[问题] 交互界面遮挡战场右下角的永久物"},
		{"Chinese locale", "zh_TW", "suggestion", "改善反馈提示", "[建议] 改善反馈提示"},
		{"blank lines and spaces", "en", "suggestion", "\r\n  \t\n  Add\t a  search box \r\nMore detail", "[Suggestion] Add a search box"},
		{"fallback language", "de", "other", "Mehr Details", "[Feedback] Mehr Details"},
		{"English problem", "en", "problem", "Cannot join a room", "[Problem] Cannot join a room"},
		{"plain mention", "zh-CN", "problem", "@someone 无法打开房间", "[问题] @\u200bsomeone 无法打开房间"},
	} {
		t.Run(test.name, func(t *testing.T) {
			_, sub := publicFixture(t)
			sub.Manifest.Context.UILanguage = test.language
			sub.Manifest.Category = test.category
			sub.Manifest.Description = test.description
			r := PublicRecord{Receipt: PublicReceipt{SubmissionID: sub.Manifest.SubmissionID}, Submission: &sub}
			if got := issueTitle(r); got != test.want {
				t.Fatalf("title = %q, want %q", got, test.want)
			}
		})
	}
}

func TestPublicIssueTitleTruncationPreservesFullDescription(t *testing.T) {
	c, sub := publicFixture(t)
	sub.Manifest.Context.UILanguage = "zh"
	sub.Manifest.Description = strings.Repeat("中文🙂", 100) + "\n补充细节"
	r := PublicRecord{Receipt: PublicReceipt{SubmissionID: sub.Manifest.SubmissionID}, Submission: &sub, Digest: sub.Digest}
	p := &GitHubPublisher{config: c, publicURL: c.PublicURL}
	title := issueTitle(r)
	if !utf8.ValidString(title) || utf8.RuneCountInString(title) != 100 || !strings.HasSuffix(title, "…") || strings.Contains(title, "\n") || strings.Contains(title, sub.Manifest.SubmissionID) {
		t.Fatalf("invalid truncated title %q", title)
	}
	if !strings.Contains(p.issueBody(r), publicFence(sub.Manifest.Description)) {
		t.Fatal("title truncation lost original feedback")
	}
}

func TestPublicIssueReadableBodyRetainsEvidence(t *testing.T) {
	c, sub := publicFixture(t)
	sub = addPublicImage(t, sub)
	sub.Manifest.Context.UILanguage = "zh"
	sub.Manifest.Context.GameMode = "forge"
	sub.Manifest.Description = "第一行\n```text\n</details>\n@someone\n尾行"
	r := PublicRecord{Receipt: PublicReceipt{SubmissionID: sub.Manifest.SubmissionID}, Submission: &sub, Digest: sub.Digest}
	p := &GitHubPublisher{config: c, publicURL: c.PublicURL}
	body := p.issueBody(r)
	visible, details, found := strings.Cut(body, "<details>\n<summary>")
	if !found || !strings.Contains(visible, "## 反馈内容") || !strings.Contains(visible, publicFence(sub.Manifest.Description)) || !strings.Contains(visible, "**环境：**") {
		t.Fatal("feedback and environment must precede folded metadata")
	}
	a := sub.Manifest.Attachments[0]
	if !strings.Contains(visible, "[截图 1]("+p.assetURL(r.Receipt.SubmissionID, a)+")") || strings.Contains(visible, "["+a.ID+"]") {
		t.Fatal("attachment link is missing or still named after its identifier")
	}
	context, _ := json.MarshalIndent(sub.Manifest.Context, "", "  ")
	attachments, _ := json.MarshalIndent(sub.Manifest.Attachments, "", "  ")
	for _, want := range []string{sub.Manifest.CreatedAt, sub.Manifest.SubmissionID, string(context), string(attachments), sub.Manifest.Disclosure.Revision, sub.Manifest.Disclosure.ProviderPolicyRevision, sub.Manifest.Disclosure.SHA256} {
		if !strings.Contains(details, want) {
			t.Fatalf("missing approved metadata %q", want)
		}
	}
	marker := "<!-- hexproof-public-v2 " + sub.Manifest.SubmissionID + " " + sub.Digest + " -->"
	if !strings.HasSuffix(body, "</details>\n\n"+marker+"\n") || strings.Contains(body, "assessment has not started") {
		t.Fatal("provenance marker changed or stale assessment status remains")
	}
	if !strings.Contains(visible, "````text\n"+sub.Manifest.Description+"\n````") {
		t.Fatal("user Markdown escaped the literal description fence")
	}
}

func TestPublicIssueEnglishBodyWithoutEmptySections(t *testing.T) {
	c, sub := publicFixture(t)
	sub.Manifest.Context = Context{UILanguage: "en"}
	r := PublicRecord{Receipt: PublicReceipt{SubmissionID: sub.Manifest.SubmissionID}, Submission: &sub, Digest: sub.Digest}
	p := &GitHubPublisher{config: c, publicURL: c.PublicURL}
	body := p.issueBody(r)
	for _, want := range []string{"## Feedback", "Technical details and tracking", "Feedback ID:"} {
		if !strings.Contains(body, want) {
			t.Fatalf("missing English text %q", want)
		}
	}
	for _, unwanted := range []string{"## Attachments", "Attachment descriptors", "**Environment:", "None."} {
		if strings.Contains(body, unwanted) {
			t.Fatalf("empty section %q", unwanted)
		}
	}
}
