#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors
"""Cache public Scryfall images for the offline Forge UI design study."""

import argparse
import json
from pathlib import Path
import time
import urllib.parse
import urllib.request

CARDS = {
    "ragavan": "Ragavan, Nimble Pilferer",
    "guide": "Guide of Souls",
    "ajani": "Ajani, Nacatl Pariah",
    "ocelot": "Ocelot Pride",
    "ravager": "Arcbound Ravager",
    "ballista": "Walking Ballista",
    "walker": "Hangarback Walker",
    "scales": "Hardened Scales",
    "foundry": "Sacred Foundry",
    "mountain": "Mountain",
    "plains": "Plains",
    "forest": "Forest",
    "citadel": "Darksteel Citadel",
    "bolt": "Lightning Bolt",
    "discharge": "Galvanic Discharge",
    "ranger": "Ranger-Captain of Eos",
    "phlage": "Phlage, Titan of Fire's Fury",
    "isamaru": "Isamaru, Hound of Konda",
    "thalia": "Thalia, Guardian of Thraben",
}


def fetch(url: str, accept: str) -> bytes:
    request = urllib.request.Request(url, headers={
        "User-Agent": "Hexproof-Forge-UI-Study/1.0",
        "Accept": accept,
    })
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def prepare(destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for key, name in CARDS.items():
        metadata = destination / f"{key}.json"
        if not metadata.exists():
            query = urllib.parse.urlencode({"exact": name})
            payload = fetch("https://api.scryfall.com/cards/named?" + query, "application/json")
            card = json.loads(payload)
            metadata.write_text(json.dumps(card, indent=2) + "\n")
            time.sleep(0.12)
        card = json.loads(metadata.read_text())
        face = card if "image_uris" in card else card["card_faces"][0]
        for variant, suffix in [("normal", "full"), ("art_crop", "art")]:
            target = destination / f"{key}-{suffix}.jpg"
            if not target.exists():
                payload = fetch(face["image_uris"][variant], "image/jpeg")
                if not payload.startswith(b"\xff\xd8"):
                    raise ValueError(f"Expected JPEG for {name}: {variant}")
                target.write_bytes(payload)
        print(f"Ready: {name}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    prepare(parser.parse_args().destination)
