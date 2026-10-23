// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

package feedback

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

// These exact fixture files are also consumed by the Qt parser. They exercise
// the additive contract without treating their synthetic refs as GitHub proof.
func TestPublicThreadSharedAIFixtures(t *testing.T) {
	for _, name := range []string{"thread-custom-question.json", "thread-delivery-history.json"} {
		t.Run(name, func(t *testing.T) {
			raw, err := os.ReadFile(filepath.Join("../../../../testdata/feedback/v2", name))
			if err != nil {
				t.Fatal(err)
			}
			var thread PublicThread
			if err = decodeClosed(raw, &thread); err != nil {
				t.Fatal("shared wire fields disagree with server", err)
			}
			if thread.SchemaVersion != 2 || !validID(thread.SubmissionID) || thread.ProjectionState != "published" || thread.CaseState != "open" || thread.RemovalState != "none" || len(thread.Items) > 5 || thread.DeliveryHistory == nil {
				t.Fatal("invalid shared conversation", thread)
			}
			if name == "thread-custom-question.json" {
				q := thread.Question
				if thread.WorkState != "needs-information" || q == nil || q.Code != "custom" || q.Description != "发生问题时是哪张牌的抓牌效果？当时使用手动模式还是 Forge 模式？" || !utcTime(q.PublishedAt) || !utcTime(q.AnswerDeadline) || len(thread.DeliveryHistory) != 0 || thread.Outcome != nil {
					t.Fatal("custom question contract changed", thread)
				}
				if len(thread.Items) != 2 || thread.Items[1].QuestionID != q.ID || thread.Items[1].Description != q.Description {
					t.Fatal("question not bound to its public conversation", thread.Items)
				}
			} else {
				if thread.WorkState != "assessing" || thread.Outcome != nil || thread.Question != nil || len(thread.DeliveryHistory) != 2 || len(thread.Items) != 5 {
					t.Fatal("historical delivery became current", thread)
				}
				for i, fact := range thread.DeliveryHistory {
					state := "source-published-awaiting-release"
					if i == 1 {
						state = "released"
					}
					if fact.InputRevision != 1 || fact.WorkflowRevision >= thread.WorkflowRevision || !utcTime(fact.PublishedAt) || fact.ProjectionID != thread.Items[i+1].SubmissionID || !reflect.DeepEqual(&fact.Outcome, thread.Items[i+1].Outcome) || !validProjectionOutcome(ProjectionRequest{WorkState: state, Outcome: &fact.Outcome}, "example/project", 42) {
						t.Fatal("historical delivery scope/reference changed", fact)
					}
				}
				if thread.DeliveryHistory[1].Outcome.Version != "3.1.0" || thread.Items[3].Kind != "reply" {
					t.Fatal("shared regression/release example changed", thread)
				}
			}
			// Compare additive wire fields semantically after server serialization;
			// other legacy fields may legitimately acquire optional empty defaults.
			encoded, err := json.Marshal(thread)
			if err != nil {
				t.Fatal(err)
			}
			var original, roundTrip map[string]any
			if json.Unmarshal(raw, &original) != nil || json.Unmarshal(encoded, &roundTrip) != nil {
				t.Fatal("fixture serialization failed")
			}
			for _, field := range []string{"question", "outcome", "deliveryHistory", "summary", "workState"} {
				if !reflect.DeepEqual(original[field], roundTrip[field]) {
					t.Fatal("server changed shared field", field, original[field], roundTrip[field])
				}
			}
		})
	}
}
