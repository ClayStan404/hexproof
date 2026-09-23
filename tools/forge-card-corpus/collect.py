#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

"""Freeze ten published representative decks per requested Constructed format.

Only public deck facts are retained in the manifest. Raw source pages and their
retrieval hashes live in the explicit build directory for reproducibility.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
from urllib.request import Request, urlopen


FORMATS = ("standard", "pioneer", "modern", "legacy")
ORIGIN = "https://www.mtggoldfish.com"


class Page(HTMLParser):
    def __init__(self, content):
        super().__init__()
        self.inputs = {}
        self.links = []
        self.text = []
        self.feed(content)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "input" and attrs.get("id", "").startswith("deck_input_"):
            self.inputs[attrs["id"]] = attrs.get("value", "")
        if tag == "a" and "href" in attrs:
            self.links.append(attrs["href"])

    def handle_data(self, data):
        self.text.append(data.strip())


def fetch(url, cache):
    path = cache / (hashlib.sha256(url.encode()).hexdigest() + ".html")
    if not path.exists():
        request = Request(url, headers={"User-Agent": "Hexproof card regression source collection"})
        with urlopen(request, timeout=30) as response:
            content = response.read()
        path.write_bytes(content)
    content = path.read_bytes()
    return Page(content.decode("utf-8")), hashlib.sha256(content).hexdigest()


def parse_deck(text):
    sections = {"mainboard": [], "sideboard": []}
    current = "mainboard"
    for line in text.splitlines():
        line = line.strip()
        if not line:
            if sections[current]:
                current = "sideboard"
            continue
        if line.lower() in ("sideboard", "sideboard:"):
            current = "sideboard"
            continue
        if line.startswith("SB: "):
            current = "sideboard"
            line = line[4:]
        match = re.fullmatch(r"(\d+) (.+)", line)
        if not match or int(match[1]) < 1:
            raise ValueError(f"Invalid registered-card line: {line!r}")
        sections[current].append({"name": match[2], "count": int(match[1])})
    main = sum(card["count"] for card in sections["mainboard"])
    side = sum(card["count"] for card in sections["sideboard"])
    if main < 60 or side > 15:
        raise ValueError(f"Invalid Constructed registration size: {main}/{side}")
    return sections


def representative(entry, cache):
    format_name, rank, url = entry
    page, sha = fetch(url, cache)
    actual_format = page.inputs["deck_input_format"]
    if actual_format != format_name:
        raise ValueError(f"Format mismatch at {url}: {actual_format}")
    deck_link = next(link for link in page.links if re.fullmatch(r"/deck/\d+", link))
    deck_id = deck_link.rsplit("/", 1)[1]
    date = next(text.removeprefix("Deck Date: ") for text in page.text if text.startswith("Deck Date: "))
    event = next((ORIGIN + link for link in page.links if link.startswith("/tournament/")), "")
    external = next((link for link in page.links if re.match(r"https://(?:www\.)?(?:mtgo\.com|melee\.gg)/", link)), "")
    return {"id": f"{format_name}-{rank:02d}-{deck_id}", "format": format_name,
            "name": page.inputs["deck_input_name"], "date": date,
            "source": ORIGIN + deck_link, "selectionSource": url, "event": event,
            "originalSource": external, "sourceSha256": sha,
            **parse_deck(page.inputs["deck_input_deck"])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    selections = []
    indexes = []
    for format_name in FORMATS:
        url = ORIGIN + "/metagame/" + format_name
        page, sha = fetch(url, args.cache)
        links = list(dict.fromkeys(link.split("#")[0] for link in page.links if link.startswith("/archetype/")))[:10]
        if len(links) != 10:
            raise ValueError(f"Expected ten distinct {format_name} archetypes")
        selections.extend((format_name, rank, ORIGIN + link) for rank, link in enumerate(links, 1))
        indexes.append({"format": format_name, "url": url, "sha256": sha})
    with ThreadPoolExecutor(max_workers=4) as pool:
        decks = list(pool.map(lambda entry: representative(entry, args.cache), selections))
    if len({deck["source"] for deck in decks}) != 40:
        raise ValueError("Representative deck IDs are not distinct")
    result = {"schema": 1, "retrievedAt": datetime.now(timezone.utc).isoformat(),
              "selection": "First ten distinct archetypes in each public metagame index; published representative list, including sideboard",
              "indexes": indexes, "decks": decks}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    cards = {card["name"] for deck in decks for section in ("mainboard", "sideboard") for card in deck[section]}
    print(f"Frozen {len(decks)} decks, {len(cards)} distinct card names: {args.output}")
    for deck in decks:
        print(deck["id"], deck["name"], deck["date"], flush=True)


if __name__ == "__main__":
    main()
