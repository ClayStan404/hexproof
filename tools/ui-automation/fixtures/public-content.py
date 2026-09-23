#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Loopback-only sponsor/news fixture for PublicContent.qml's three launches."""

import argparse
from datetime import datetime, timedelta, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-file", required=True, type=Path)
    args = parser.parse_args()
    args.state_file.parent.mkdir(parents=True, exist_ok=True)
    avatar = (ROOT / "apps/client-qt/qml/assets/card-back.jpg").read_bytes()
    now = datetime.now(timezone.utc)
    state = {"phase": 1, "requests": {}, "bodies": {}}

    def save():
        temporary = args.state_file.with_suffix(".tmp")
        temporary.write_text(json.dumps(state, indent=2) + "\n")
        temporary.replace(args.state_file)

    def data():
        phase = state["phase"]
        ids = ["native-expired", "native-active"] if phase == 1 else ["native-active"]
        if phase == 3:
            ids.append("native-newcomer")
        sponsors = {"schemaVersion": 1, "revision": phase + 1, "sponsors": [
            {"id": value, "name": {"native-expired": "Expired supporter", "native-active": "Active supporter",
                                    "native-newcomer": "New supporter"}[value],
             "tier": "ragavan", "profileUrl": "", "avatar": {"path": "avatars/profile.jpg", "sha256": hashlib.sha256(avatar).hexdigest()}}
            for value in ids]}
        entries = []
        for identifier, days, title in (("maintenance", 0, "Public content is available offline"),
                                        ("history", 200, "A retained historical announcement")):
            entries.append({"id": identifier, "notificationRevision": 1,
                            "publishedAt": (now - timedelta(days=days, minutes=1)).isoformat(timespec="seconds").replace("+00:00", "Z"),
                            "title": {"en": title, "zh": "离线公告验证" if days == 0 else "历史公告验证"},
                            "body": {"en": "This local test checks cached announcements, read state and retained history.\n\nNo public service is changed.",
                                     "zh": "本地验证公告缓存、已读状态与历史保留。\n\n本次验证使用隔离配置和本地服务。"}})
        news = {"schemaVersion": 1, "revision": 2,
                "display": {"mode": "recent", "recentDays": 90, "selectedIds": []}, "announcements": entries}
        files = {"/avatars/profile.jpg": avatar}
        index = {"schemaVersion": 1, "revision": phase}
        for kind, document in (("sponsors", sponsors), ("announcements", news)):
            payload = (json.dumps(document, ensure_ascii=False, indent=2) + "\n").encode()
            files["/" + kind + ".json"] = payload
            index[kind] = {"revision": document["revision"], "path": kind + ".json", "sha256": hashlib.sha256(payload).hexdigest()}
        files["/index.json"] = json.dumps(index).encode()
        return files

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            state["requests"][self.path] = state["requests"].get(self.path, 0) + 1
            if self.path in ("/advance/2", "/advance/3"):
                state["phase"] = int(self.path[-1])
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"ok")
                save()
                return
            payload = data().get(self.path)
            if payload is None:
                self.send_error(404)
                return
            etag = '"' + hashlib.sha256(payload).hexdigest() + '"'
            unchanged = self.headers.get("If-None-Match") == etag
            self.send_response(304 if unchanged else 200)
            self.send_header("ETag", etag)
            self.send_header("Content-Length", "0" if unchanged else str(len(payload)))
            self.end_headers()
            if not unchanged:
                self.wfile.write(payload)
                state["bodies"][self.path] = state["bodies"].get(self.path, 0) + 1
            save()

        def log_message(self, *_args):
            pass

    server = HTTPServer(("127.0.0.1", 0), Handler)
    state["indexUrl"] = f"http://127.0.0.1:{server.server_port}/index.json"
    save()
    print(state["indexUrl"], flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
