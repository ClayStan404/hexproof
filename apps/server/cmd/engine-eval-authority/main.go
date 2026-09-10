// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hexproof contributors

// engine-eval-authority is a local laboratory helper, not a server endpoint.
// It exercises the production Forge response builder against real Java prompts.
// Actor identity is supplied by the trusted test; WebSocket authentication is
// tested independently by the engineintegration tests.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"hexproof/server/internal/rulesengine/forge"
)

type request struct {
	Prompt   json.RawMessage `json:"prompt"`
	Actor    int             `json:"actor"`
	PromptID int64           `json:"promptId"`
	Label    string          `json:"label"`
}

type result struct {
	Accepted bool            `json:"accepted"`
	Reason   string          `json:"reason,omitempty"`
	Response json.RawMessage `json:"response,omitempty"`
}

func evaluate(input request) result {
	view, err := forge.NormalizePrompt(input.Prompt)
	if err != nil {
		return result{Reason: err.Error()}
	}
	responseID := ""
	for _, option := range view.Options {
		if strings.HasPrefix(option.Label, "Play ") && option.Label == input.Label {
			responseID = option.ResponseID
			break
		}
	}
	if responseID == "" || input.Label == "" {
		return result{Reason: "Requested land is not offered by the real prompt"}
	}
	response, err := forge.BuildPromptResponse(input.Prompt, input.Actor,
		input.PromptID, forge.PromptResponse{ResponseID: responseID})
	if err != nil {
		return result{Reason: err.Error()}
	}
	return result{Accepted: true, Response: json.RawMessage(response)}
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 65536), 4<<20)
	writer := json.NewEncoder(os.Stdout)
	for scanner.Scan() {
		var input request
		var output result
		if err := json.Unmarshal(scanner.Bytes(), &input); err != nil {
			output.Reason = err.Error()
		} else {
			output = evaluate(input)
		}
		if err := writer.Encode(output); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}
	if err := scanner.Err(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
