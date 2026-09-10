#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Ephemeral loopback test adapter, not XMage's native server or production auth."""

import argparse
import asyncio
import json
import os
from pathlib import Path
import secrets
import signal
import sys


class Broker:
    def __init__(self, args):
        self.args = args
        payload = json.loads(args.workload.read_text())
        self.spec = next(w for w in payload["workloads"] if w["id"] == args.workload_id)
        self.tokens = {str(i): secrets.token_urlsafe(24) for i in range(len(self.spec["players"]))}
        self.tokens["-1"] = secrets.token_urlsafe(24)
        self.operator = secrets.token_urlsafe(24)
        self.roles = {token: int(role) for role, token in self.tokens.items()}
        self.clients = {}
        self.connections = set()
        self.views = {}
        self.pending = None
        self.worker = None
        self.done = asyncio.Event()
        self.last_result = None

    async def send(self, writer, event):
        writer.write(json.dumps(event).encode() + b"\n")
        await asyncio.wait_for(writer.drain(), 2)

    def state(self, role):
        decision = None
        if self.pending and self.pending["actor"] == role:
            decision = {key: value for key, value in self.pending.items() if key != "views"}
        return {"type": "state", "engine": "XMage", "viewer": role,
                "view": self.views.get(role), "decision": decision,
                "scope": "ephemeral loopback test adapter"}

    async def broadcast(self):
        for role, writer in list(self.clients.items()):
            try:
                await self.send(writer, self.state(role))
            except (OSError, asyncio.TimeoutError, ConnectionError):
                writer.close()

    async def input(self, reader, writer):
        self.connections.add(writer)
        role = None
        try:
            line = await asyncio.wait_for(reader.readline(), 5)
            request = json.loads(line)
            if not isinstance(request, dict):
                raise ValueError("invalid_attach_shape")
            token = request.get("token")
            if request.get("type") != "attach" or not isinstance(token, str) or token not in self.roles and token != self.operator:
                await self.send(writer, {"type": "error", "reason": "invalid_test_token"})
                return
            role = self.roles.get(token, -2)
            if role == -2:
                await self.send(writer, {"type": "attached", "role": "test_operator"})
            else:
                previous = self.clients.get(role)
                if previous:
                    previous.close()
                self.clients[role] = writer
                await self.send(writer, {"type": "attached", "viewer": role})
                await self.send(writer, self.state(role))
            while line := await reader.readline():
                try:
                    request = json.loads(line)
                    if not isinstance(request, dict):
                        raise ValueError("invalid_request_shape")
                    if role >= -1 and self.clients.get(role) is not writer:
                        raise ValueError("replaced_connection")
                    if request.get("type") == "cancel" and role == -2:
                        self.worker.stdin.write(b'{"type":"test_cancel","requestId":"loopback-operator"}\n')
                        await self.worker.stdin.drain()
                        await self.send(writer, {"type": "cancelling", "scope": "test_operator"})
                        continue
                    if request.get("type") == "refresh" and role >= -1:
                        await self.send(writer, self.state(role))
                        continue
                    if request.get("type") != "respond":
                        raise ValueError("unsupported_request")
                    if role < 0 or not self.pending or self.pending["actor"] != role:
                        raise ValueError("not_pending_actor")
                    if type(request.get("id")) is not int or request["id"] != self.pending["id"]:
                        raise ValueError("stale_decision")
                    if "actor" in request and (type(request["actor"]) is not int or request["actor"] != role):
                        raise ValueError("actor_spoof")
                    response = request.get("response")
                    encoded = json.dumps(response, sort_keys=True, separators=(",", ":"))
                    if not any(json.dumps(action["response"], sort_keys=True, separators=(",", ":")) == encoded
                               for action in self.pending["actions"]):
                        raise ValueError("unoffered_response")
                    forwarded = {"type": "respond", "id": self.pending["id"], "actor": role, "response": response}
                    # Consume before yielding; concurrent/replayed sockets cannot
                    # reuse the outstanding engine decision.
                    self.pending = None
                    # Queue the acknowledgement before forwarding, without an
                    # intervening await: a fast engine cannot overtake the ack.
                    writer.write(json.dumps({"type": "accepted", "id": forwarded["id"]}).encode() + b"\n")
                    self.worker.stdin.write(json.dumps(forwarded).encode() + b"\n")
                    await self.worker.stdin.drain()
                    await asyncio.wait_for(writer.drain(), 2)
                except (ValueError, TypeError, KeyError) as error:
                    await self.send(writer, {"type": "error", "reason": str(error)})
        except (OSError, ValueError, TypeError, asyncio.TimeoutError, ConnectionError, asyncio.LimitOverrunError):
            pass
        finally:
            self.connections.discard(writer)
            if role in self.clients and self.clients[role] is writer:
                del self.clients[role]
            writer.close()
            try:
                await writer.wait_closed()
            except OSError:
                pass

    async def output(self, trace):
        try:
            while line := await self.worker.stdout.readline():
                event = json.loads(line)
                trace.write(json.dumps(event) + "\n")
                trace.flush()
                if event["type"] == "decision":
                    self.views = {view["viewer"]: view for view in event["views"]}
                    self.pending = event
                    await self.broadcast()
                elif event["type"] == "result":
                    print("BROKER_STAGE received worker result", file=sys.stderr, flush=True)
                    self.last_result = event
                    self.pending = None
                    self.views = {view["viewer"]: view for view in event["views"]}
                    for role, writer in list(self.clients.items()):
                        redacted = {key: value for key, value in event.items() if key not in {"views", "view"}}
                        redacted["view"] = self.views[role]
                        await self.send(writer, redacted)
                    self.done.set()
                    print("BROKER_STAGE terminal projections sent", file=sys.stderr, flush=True)
                    return
                elif event["type"] == "error":
                    raise RuntimeError(f"Unexpected worker adapter error: {event}")
        finally:
            self.done.set()

    async def run(self):
        loop = asyncio.get_running_loop()
        current = asyncio.current_task()
        for signum in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(signum, current.cancel)
        self.args.output.mkdir(parents=True, exist_ok=False)
        command = [sys.executable, str(Path(__file__).with_name("bridge.py").resolve()),
                   "--run-dir", str(self.args.run_dir.resolve()), "--workload", str(self.args.workload.resolve()),
                   "--workload-id", self.args.workload_id, "--profile", str(self.args.output / "profile")]
        (self.args.output / "command.json").write_text(json.dumps(command, indent=2) + "\n")
        with (self.args.output / "worker.stderr.log").open("w") as errors, (self.args.output / "worker.events.jsonl").open("w") as trace:
            self.worker = await asyncio.create_subprocess_exec(*command, stdin=asyncio.subprocess.PIPE,
                    stdout=asyncio.subprocess.PIPE, stderr=errors, limit=4 * 1024 * 1024, start_new_session=True)
            server = await asyncio.start_server(self.input, "127.0.0.1", 0, limit=65536)
            port = server.sockets[0].getsockname()[1]
            ready = {"type": "broker_ready", "host": "127.0.0.1", "port": port,
                     "testTokens": self.tokens, "testOperatorToken": self.operator,
                     "scope": "random ephemeral test credentials; never production credentials"}
            (self.args.output / "connection.json").write_text(json.dumps(ready, indent=2) + "\n")
            print(json.dumps(ready), flush=True)
            task = asyncio.create_task(self.output(trace))
            try:
                await asyncio.wait_for(self.done.wait(), 180)
                print("BROKER_STAGE done signalled", file=sys.stderr, flush=True)
                await task
                print("BROKER_STAGE worker reader complete", file=sys.stderr, flush=True)
                self.worker.stdin.close()
                await asyncio.wait_for(self.worker.wait(), 10)
                print("BROKER_STAGE worker exited", file=sys.stderr, flush=True)
            finally:
                server.close()
                # Server.wait_closed also waits for accepted connections on
                # current Python. Close every socket, including the operator.
                for writer in list(self.connections):
                    writer.close()
                await asyncio.wait_for(server.wait_closed(), 5)
                if self.worker.returncode is None:
                    os.killpg(self.worker.pid, signal.SIGTERM)
                    try:
                        await asyncio.wait_for(self.worker.wait(), 5)
                    except asyncio.TimeoutError:
                        os.killpg(self.worker.pid, signal.SIGKILL)
                        await self.worker.wait()
                if not task.done():
                    task.cancel()
            (self.args.output / "result.json").write_text(json.dumps({"workerExit": self.worker.returncode,
                    "result": self.last_result, "scope": "test adapter lifecycle; not native XMage server authentication"}, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--workload", type=Path, required=True)
    parser.add_argument("--workload-id", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output = args.output.resolve()
    try:
        asyncio.run(Broker(args).run())
    except asyncio.CancelledError:
        pass


if __name__ == "__main__":
    main()
