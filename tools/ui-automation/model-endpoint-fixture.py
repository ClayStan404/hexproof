#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Loopback-only Chat Completions fixture; never a real model or strength test."""

import argparse
from collections import Counter
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path


def answer(prompt):
    """A deliberately passive policy for the simple constructed GUI fixture."""
    result = {"promptId": prompt["promptId"], "responseId": "$submit"}
    kind = prompt["kind"]
    if kind == "chooseAction":
        options = prompt["options"]
        preferred = next((o for o in options if o["responseId"] == "test:allowed"), None)
        preferred = preferred or next((o for o in options if o["responseId"] == "$pass"), None)
        if preferred is None:
            raise ValueError("Fixture requires a pass or synthetic test action")
        result["responseId"] = preferred["responseId"]
    elif kind in ("acknowledge", "revealCards", "diceRolled"):
        result["responseId"] = "$ack"
    elif kind == "mulligan":
        result["responseId"] = "$keep"
    elif kind in ("chooseBoolean", "chooseFromSelection"):
        result["choiceIds"] = [prompt["choices"][0]["responseId"]]
    elif kind in ("chooseAttackers", "chooseBlockers"):
        result["assignments"] = []
    elif kind == "chooseCards":
        candidates = [c for c in prompt["cards"] if not c.get("readOnly", False)]
        result["cardIds"] = [c["id"] for c in candidates[:prompt["minCardSelections"]]]
    elif kind == "chooseNumber":
        result["chosenNumber"] = prompt["minNumber"]
    else:
        raise ValueError("Unsupported fixture prompt: " + kind)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="New evidence directory")
    parser.add_argument("--reject-first-decision", action="store_true",
                        help="Reject the first decision and its repair to exercise explicit retry")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    counts = Counter()
    failures_remaining = 2 if args.reject_first_decision else 0

    def record():
        temporary = args.output / "metrics.tmp"
        temporary.write_text(json.dumps(dict(counts), indent=2) + "\n")
        temporary.replace(args.output / "metrics.json")

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            nonlocal failures_remaining
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if self.path != "/v1/chat/completions" or not 0 < length <= 2 * 1024 * 1024:
                    raise ValueError("Unexpected request")
                body = json.loads(self.rfile.read(length))
                observations = [json.loads(m["content"]) for m in body["messages"]
                                if m["role"] == "user"]
                prompt = observations[0]["prompt"]
                synthetic = any(o.get("responseId") == "test:allowed" for o in prompt.get("options", []))
                counts["connectionTests" if synthetic else "decisions"] += 1
                counts[prompt["kind"]] += 1
                reply = answer(prompt)
                if not synthetic and failures_remaining:
                    failures_remaining -= 1
                    counts["injectedRejections"] += 1
                    reply = {"promptId": prompt["promptId"], "responseId": "fixture-invalid-choice"}
                response = {"choices": [{"message": {"role": "assistant", "content": json.dumps(reply)},
                                          "finish_reason": "stop"}],
                            "usage": {"prompt_tokens": 100, "completion_tokens": 20}}
                record()
                encoded = json.dumps(response).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(encoded)))
                self.end_headers()
                self.wfile.write(encoded)
            except (ValueError, KeyError, IndexError, TypeError):
                counts["fixtureErrors"] += 1
                record()
                self.send_error(400, "Unsupported synthetic fixture input")

    with HTTPServer(("127.0.0.1", 0), Handler) as server:
        endpoint = f"http://127.0.0.1:{server.server_port}/v1"
        (args.output / "endpoint.json").write_text(json.dumps({"endpoint": endpoint}) + "\n")
        print(endpoint, flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
