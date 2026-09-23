#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Check a home node's public TLS, health, WebSocket relay and optional room flow.

Uses only the Python standard library. TLS certificate verification stays on.
Reports safe capability/latency metadata, never resume credentials or raw frames.
--room creates and explicitly leaves one synthetic waiting room on this endpoint.
This exercises the ordinary WSS relay, not WebRTC direct or TURN transport.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import socket
import ssl
import struct
import time
from urllib.parse import urlsplit, urlunsplit
from urllib.request import ProxyHandler, build_opener


MAX_FRAME = 16 * 1024**2
HTTP = build_opener(ProxyHandler({}))


class WebSocket:
    def __init__(self, url: str):
        parts = urlsplit(url)
        if parts.scheme not in ("ws", "wss") or parts.username or parts.password or not parts.hostname:
            raise ValueError("Expected an ordinary ws/wss endpoint without credentials")
        port = parts.port or (443 if parts.scheme == "wss" else 80)
        raw = socket.create_connection((parts.hostname, port), timeout=15)
        self.sock = (ssl.create_default_context().wrap_socket(raw, server_hostname=parts.hostname)
                     if parts.scheme == "wss" else raw)
        self.buffer = bytearray()
        self.last = {}
        key = base64.b64encode(os.urandom(16)).decode()
        path = parts.path or "/"
        if parts.query:
            path += "?" + parts.query
        request = (f"GET {path} HTTP/1.1\r\nHost: {parts.netloc}\r\nUpgrade: websocket\r\n"
                   f"Connection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {key}\r\n\r\n")
        self.sock.sendall(request.encode())
        while b"\r\n\r\n" not in self.buffer:
            incoming = self.sock.recv(4096)
            if not incoming:
                raise EOFError("WebSocket closed during handshake")
            self.buffer.extend(incoming)
            if len(self.buffer) > 65536:
                raise ValueError("Oversized WebSocket handshake")
        header, remaining = bytes(self.buffer).split(b"\r\n\r\n", 1)
        self.buffer = bytearray(remaining)
        lines = header.decode("ascii").split("\r\n")
        if lines[0].split()[1] != "101":
            raise ValueError(f"WebSocket upgrade failed with HTTP {lines[0].split()[1]}")
        fields = {name.lower(): value.strip() for name, value in
                  (line.split(":", 1) for line in lines[1:] if ":" in line)}
        expected = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        if fields.get("sec-websocket-accept", "") != expected:
            raise ValueError("Invalid WebSocket accept proof")

    def read(self, length: int) -> bytes:
        while len(self.buffer) < length:
            incoming = self.sock.recv(min(65536, length - len(self.buffer)))
            if not incoming:
                raise EOFError("WebSocket closed before completing the response")
            self.buffer.extend(incoming)
        result = bytes(self.buffer[:length])
        del self.buffer[:length]
        return result

    def frame(self, opcode: int, data: bytes) -> None:
        mask = os.urandom(4)
        length = len(data)
        prefix = bytes([0x80 | opcode, 0x80 | (length if length < 126 else 126 if length < 65536 else 127)])
        if length >= 126:
            prefix += struct.pack("!H" if length < 65536 else "!Q", length)
        payload = bytes(value ^ mask[index % 4] for index, value in enumerate(data))
        self.sock.sendall(prefix + mask + payload)

    def send(self, kind: str, request_id: str, payload: dict) -> None:
        self.frame(1, json.dumps({"type": kind, "id": request_id, "payload": payload}).encode())

    def receive(self) -> dict:
        message = bytearray()
        while True:
            first, second = self.read(2)
            opcode = first & 0x0F
            length = second & 0x7F
            if length in (126, 127):
                length = struct.unpack("!H" if length == 126 else "!Q", self.read(2 if length == 126 else 8))[0]
            if second & 0x80 or length > MAX_FRAME:
                raise ValueError("Invalid or oversized server frame")
            data = self.read(length)
            if opcode == 8:
                raise EOFError("Server closed the WebSocket")
            if opcode == 9:
                self.frame(10, data)
                continue
            if opcode == 10:
                continue
            if opcode not in (0, 1, 2):
                raise ValueError("Invalid WebSocket opcode")
            message.extend(data)
            if len(message) > MAX_FRAME:
                raise ValueError("Oversized server message")
            if first & 0x80:
                return json.loads(message)

    def until(self, kind: str) -> dict:
        for _ in range(100):
            result = self.receive()
            self.last[result.get("type")] = result.get("payload", {})
            if result.get("type") == "error":
                raise ValueError("Server rejected smoke operation: " + str(result.get("payload", {}).get("code", "unknown")))
            if result.get("type") == kind:
                return result["payload"]
        raise ValueError("Expected response not received within message bound")

    def close(self) -> None:
        try:
            self.frame(8, struct.pack("!H", 1000))
        except OSError:
            pass
        self.sock.close()


def smoke(endpoint: str, version: str, expect_forge: bool, room: bool,
          expect_ai: bool = False) -> dict:
    parts = urlsplit(endpoint)
    if not parts.path.endswith("/ws"):
        raise ValueError("Endpoint must end in /ws")
    health = urlunsplit(("https" if parts.scheme == "wss" else "http", parts.netloc,
                        parts.path[:-3] + "/healthz", "", ""))
    started = time.monotonic()
    with HTTP.open(health, timeout=15) as response:
        if response.status != 200:
            raise ValueError("Home node is not healthy")
        response.read(65536)
    health_ms = round((time.monotonic() - started) * 1000)
    started = time.monotonic()
    client = WebSocket(endpoint)
    created = False
    try:
        client.send("session.hello", "home-smoke-hello", {"displayName": "HomeNodeSmoke",
                    "clientVersion": version, "protocol": "hexproof.v1"})
        welcome = client.until("session.welcome")
        welcome_ms = round((time.monotonic() - started) * 1000)
        if welcome.get("serverVersion") != version or welcome.get("v") != "hexproof.v1":
            raise ValueError("Unexpected game-server version or protocol")
        if (expect_forge or expect_ai) and not welcome.get("forgeRulesAvailable"):
            raise ValueError("Home node did not advertise Forge availability")
        if expect_ai and not welcome.get("forgeAIAvailable"):
            raise ValueError("Home node did not advertise native Forge AI availability")
        if room:
            client.send("room.create", "home-smoke-create", {"name": "HomeNodeSmoke",
                        "format": "modern", "deckFormat": "modern", "rulesMode": "manual",
                        "matchMode": "bo1", "allowSpectators": False})
            client.until("room.created")
            created = True
            client.send("room.leave", "home-smoke-leave", {})
            client.until("room.disbanded")
            created = False
        return {"endpoint": endpoint, "healthMs": health_ms, "welcomeMs": welcome_ms,
                "serverVersion": welcome["serverVersion"], "forgeRulesAvailable": bool(welcome.get("forgeRulesAvailable")),
                "forgeAIAvailable": bool(welcome.get("forgeAIAvailable")),
                "transportTested": "wss-relay" if parts.scheme == "wss" else "ws",
                "waitingRoomCreatedAndLeft": room}
    finally:
        try:
            if created:
                client.send("room.leave", "home-smoke-cleanup", {})
        finally:
            client.close()


def verify_projection(snapshot: dict, seat: int) -> None:
    if not snapshot.get("gameId"):
        raise ValueError("Forge did not provide a game projection")
    for zone in snapshot.get("zones", []):
        hidden = zone.get("zone") == "library" or (zone.get("zone") == "hand" and zone.get("ownerSeat") != seat)
        if (zone.get("zone") == "hand" and zone.get("ownerSeat") == seat
                and len(zone.get("cards", [])) != zone.get("count", 0)):
            raise ValueError("Forge projection omitted cards from the player's hand")
        for card in zone.get("cards", []):
            if hidden and (card.get("identity") or card.get("visible")):
                raise ValueError("Forge projection disclosed a hidden card")
            if zone.get("zone") == "hand" and zone.get("ownerSeat") == seat and (not card.get("identity") or not card.get("visible")):
                raise ValueError("Forge projection omitted the player's own hand")


def forge_smoke(endpoint: str, version: str) -> dict:
    clients = []
    created = False
    started = time.monotonic()
    try:
        for name in ("HomeForgeSmokeA", "HomeForgeSmokeB", "HomeForgeSmokeObserver"):
            client = WebSocket(endpoint)
            client.sock.settimeout(90)
            clients.append(client)
            client.send("session.hello", "hello", {"displayName": name, "clientVersion": version,
                        "protocol": "hexproof.v1"})
            client.until("session.welcome")
        host, guest, observer = clients
        host.send("room.create", "create", {"name": "HomeForgeSmoke", "format": "modern",
                  "deckFormat": "custom", "rulesMode": "forge", "hostingMode": "server",
                  "matchMode": "bo1", "maxSeats": 2, "allowSpectators": True, "cardLoadMode": "background"})
        room_id = host.until("room.created")["roomId"]
        created = True
        guest.send("room.join", "join", {"roomId": room_id})
        guest.until("room.joined")
        deck = {"name": "Synthetic Smoke", "format": "modern", "deckFormat": "custom",
                "mainboard": [{"name": "Mountain", "count": 24, "setCode": "M11", "collectorNumber": "242"},
                              {"name": "Lightning Bolt", "count": 36, "setCode": "M11", "collectorNumber": "149"}],
                "sideboard": [{"name": "Ensnaring Bridge", "count": 1, "setCode": "7ED", "collectorNumber": "294★"},
                              {"name": "Liquimetal Coating", "count": 1, "setCode": "BRR", "collectorNumber": "91z"}]}
        for client in (host, guest):
            client.send("deck.select", "deck", deck)
            client.until("deck.selected")
            client.send("player.ready", "ready", {"ready": True})
            client.until("player.ready_changed")
        prompts = []
        for seat, client in enumerate((host, guest)):
            prompts.append(client.until("rules.prompt"))
            verify_projection(client.last.get("rules.snapshot", {}), seat)
        observer.send("room.join", "observe", {"roomId": room_id, "asSpectator": True})
        observer_snapshot = observer.until("rules.snapshot")
        verify_projection(observer_snapshot, -1)
        game_ids = {client.last["rules.snapshot"]["gameId"] for client in clients}
        if len(game_ids) != 1:
            raise ValueError("Forge viewers received different games")
        actor = next((index for index, prompt in enumerate(prompts) if prompt.get("pending")), None)
        if actor is None:
            raise ValueError("Forge did not publish an initial native decision")
        choices = {option.get("responseId") for option in prompts[actor].get("options", [])}
        response = next((value for value in ("$keep", "$ack", "$pass", "$yes", "$no") if value in choices), None)
        answer = {"promptId": prompts[actor]["promptId"], "responseId": response}
        if response is None and prompts[actor].get("kind") == "chooseBoolean" and prompts[actor].get("choices"):
            answer.update(responseId="$submit", choiceIds=[prompts[actor]["choices"][0]["responseId"]])
        elif response is None:
            raise ValueError("No simple synthetic response for native decision: " + str(prompts[actor].get("kind")))
        clients[actor].send("rules.respond", "decision", answer)
        clients[actor].until("rules.responded")
        host.send("game.concede", "concede", {})
        host.until("game.conceded")
        host.send("room.leave", "cleanup", {})
        host.until("room.disbanded")
        created = False
        return {"nativeForgeStarted": True, "specialTreatmentSideboardRegistered": True, "nativeDecisionAccepted": True,
                "ownerOpponentSpectatorProjectionPrivacy": True, "concededAndDisbanded": True,
                "elapsedMs": round((time.monotonic() - started) * 1000)}
    finally:
        if created:
            try:
                clients[0].send("room.leave", "cleanup-after-failure", {})
            except OSError:
                pass
        for client in reversed(clients):
            client.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("endpoint")
    parser.add_argument("--version", default="2.0.6")
    parser.add_argument("--expect-forge", action="store_true")
    parser.add_argument("--expect-ai", action="store_true",
                        help="Require native Forge AI support in the real game-server welcome")
    parser.add_argument("--room", action="store_true")
    parser.add_argument("--forge-game", action="store_true",
                        help="Start a synthetic two-player Forge game, check privacy, concede and leave")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        report = smoke(args.endpoint, args.version, args.expect_forge or args.forge_game,
                       args.room, args.expect_ai)
        if args.forge_game:
            report["forgeGame"] = forge_smoke(args.endpoint, args.version)
        result = json.dumps(report, indent=2) + "\n"
        if args.output:
            args.output.write_text(result)
        print(result, end="")
    except (ValueError, OSError, EOFError) as error:
        parser.exit(1, f"Home smoke failed: {error}\n")


if __name__ == "__main__":
    main()
