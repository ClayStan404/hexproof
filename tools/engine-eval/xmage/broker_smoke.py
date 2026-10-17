#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Disconnect/reconnect actual loopback sockets around a live HumanPlayer decision."""

import argparse
import json
from pathlib import Path
import selectors
import shutil
import socket
import subprocess
import sys
import tempfile


class Client:
    def __init__(self, ready, token, trace):
        self.socket = socket.create_connection((ready["host"], ready["port"]), timeout=10)
        self.socket.settimeout(10)
        self.stream = self.socket.makefile("rwb")
        self.trace = trace
        self.send({"type": "attach", "token": token})
        self.attached = self.receive()

    def send(self, message):
        self.trace.write(json.dumps({"sent": {k: v for k, v in message.items() if k != "token"}}) + "\n")
        self.trace.flush()
        self.stream.write(json.dumps(message).encode() + b"\n")
        self.stream.flush()

    def receive(self):
        line = self.stream.readline()
        if not line:
            raise AssertionError("Socket closed before expected evidence")
        message = json.loads(line)
        self.trace.write(json.dumps({"received": message}) + "\n")
        self.trace.flush()
        return message

    def decision(self):
        while True:
            message = self.receive()
            if message.get("decision"):
                return message

    def close(self):
        self.stream.close()
        self.socket.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--workload", type=Path, default=Path(__file__).parent.parent / "workloads.json")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="loopback-", dir=args.output.resolve()))
    print(output, flush=True)
    shutil.copy2(__file__, output / "driver.py")
    shutil.copy2(Path(__file__).with_name("broker.py"), output / "broker.py")
    command = [sys.executable, str(Path(__file__).with_name("broker.py").resolve()), "--run-dir", str(args.run_dir.resolve()),
               "--workload", str(args.workload.resolve()), "--workload-id", "limited_green_40", "--output", str(output / "broker")]
    (output / "command.json").write_text(json.dumps(command, indent=2) + "\n")
    clients = []
    with (output / "stderr.log").open("w") as errors, (output / "sockets.jsonl").open("w") as trace:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=errors, text=True)
        try:
            selector = selectors.DefaultSelector()
            selector.register(process.stdout, selectors.EVENT_READ)
            assert selector.select(10), "Broker did not become ready"
            ready = json.loads(process.stdout.readline())
            selector.close()
            invalid = Client(ready, "invalid-test-token", trace)
            clients.append(invalid)
            assert invalid.attached == {"type": "error", "reason": "invalid_test_token"}
            invalid.close()
            clients.remove(invalid)
            a = Client(ready, ready["testTokens"]["0"], trace)
            clients.append(a)
            first = a.decision()
            decision = first["decision"]
            b = Client(ready, ready["testTokens"]["1"], trace)
            spectator = Client(ready, ready["testTokens"]["-1"], trace)
            clients.extend([b, spectator])
            b_state = b.receive()
            spectator_state = spectator.receive()
            assert b_state["decision"] is None and spectator_state["decision"] is None
            own_hand = [card["id"] for zone in first["view"]["zones"] if zone["zone"] == "hand" for card in zone["cards"]]
            assert own_hand
            for other in [b_state, spectator_state]:
                assert all(card not in json.dumps(other) for card in own_hand)
                assert "views" not in other and "actions" not in other
            b_hand = [card["id"] for zone in b_state["view"]["zones"] if zone["zone"] == "hand" for card in zone["cards"]]
            assert b_hand
            for other in [first, spectator_state]:
                assert all(card not in json.dumps(other) for card in b_hand)
            spectator.send({"type": "refresh", "viewer": 0})
            assert spectator.receive() == spectator_state, "Client-supplied viewer changed its authenticated projection"
            b.send({"type": "cancel"})
            assert b.receive()["reason"] == "unsupported_request"
            keep = next(action for action in decision["actions"] if action["category"] == "keep")
            response = {"type": "respond", "id": decision["id"], "actor": 0, "response": keep["response"]}
            for client in [b, spectator]:
                client.send(response)
                assert client.receive()["reason"] == "not_pending_actor"
            for malformed, reason in [({**response, "actor": 1}, "actor_spoof"),
                                      ({**response, "id": True}, "stale_decision"),
                                      ({**response, "response": {"boolean": 0}}, "unoffered_response")]:
                a.send(malformed)
                assert a.receive()["reason"] == reason
            # Real transport disconnect while the engine is waiting: no synthetic
            # engine state reload, and no reply is forwarded to HumanPlayer.
            a.close()
            clients.remove(a)
            a = Client(ready, ready["testTokens"]["0"], trace)
            clients.append(a)
            resumed = a.decision()
            assert resumed["decision"] == decision and resumed["view"] == first["view"]
            a.send(response)
            assert a.receive()["type"] == "accepted"
            b_decision = b.decision()["decision"]
            b.close()
            clients.remove(b)
            b = Client(ready, ready["testTokens"]["1"], trace)
            clients.append(b)
            assert b.decision()["decision"] == b_decision
            b.send({**response, "actor": 1})
            assert b.receive()["reason"] == "stale_decision"
            b_keep = next(action for action in b_decision["actions"] if action["category"] == "keep")
            b.send({"type": "respond", "id": b_decision["id"], "actor": 1, "response": b_keep["response"]})
            assert b.receive()["type"] == "accepted"
            # Advance actual priority after reconnect until A can play a land.
            landed = False
            for _ in range(50):
                state = a.decision()
                current = state["decision"]
                lands = [action for action in current["actions"] if action["category"] == "land"]
                action = lands[0] if lands else next(action for action in current["actions"] if action["category"] == "pass")
                before = sum(len(zone["cards"]) for zone in state["view"]["zones"] if zone["owner"] == 0 and zone["zone"] == "battlefield")
                a.send({"type": "respond", "id": current["id"], "actor": 0, "response": action["response"]})
                assert a.receive()["type"] == "accepted"
                if lands:
                    after = a.decision()
                    total = sum(len(zone["cards"]) for zone in after["view"]["zones"] if zone["owner"] == 0 and zone["zone"] == "battlefield")
                    assert total == before + 1
                    landed = True
                    break
                b_current = b.decision()["decision"]
                passing = next(action for action in b_current["actions"] if action["category"] == "pass")
                b.send({"type": "respond", "id": b_current["id"], "actor": 1, "response": passing["response"]})
                assert b.receive()["type"] == "accepted"
            assert landed, "No continued land action after actual reconnect"
            operator = Client(ready, ready["testOperatorToken"], trace)
            clients.append(operator)
            operator.send({"type": "cancel"})
            assert operator.receive()["type"] == "cancelling"
            assert process.wait(timeout=15) == 0
            worker = json.loads((output / "broker/result.json").read_text())
            assert worker["workerExit"] == 0 and worker["result"]["cancelled"]
            result = {"status": "PASS", "layer": "adapter", "scope": "new ephemeral loopback adapter, not upstream/production authentication",
                      "invalidTokenRejected": True, "crossActorAndSpectatorRejected": True, "typedResponseRejected": True,
                      "twoRealSocketReconnectsPreserveDecision": True, "staleDecisionRejected": True,
                      "privateHandIdsAbsentFromOtherSockets": True, "continuedLandAction": True, "cancelledWorkerExited": True}
            (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
            print(json.dumps(result), flush=True)
        finally:
            for client in clients:
                client.close()
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=12)
            process.stdout.close()


if __name__ == "__main__":
    main()
