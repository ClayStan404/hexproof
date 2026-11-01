# In-match keyword reference

The manual and Forge match views provide an offline, read-only keyword reference.
Players can browse or search without selecting a card. It reads only bundled
reference data and never examines a hand, changes a table, sends a game command,
or performs a Forge input. The reference blocks table shortcuts while open and
returns usable focus when closed. All displayed reference text is plain text.

## Source and coverage

`apps/client-qt/resources/keyword-reference.json` contains original English and
Chinese summaries, rule numbers, bilingual lookup names and aliases. The rules
authority is Wizards of the Coast's **Magic: The Gathering Comprehensive Rules,
effective September 25, 2026**, linked from the
[official rules page](https://magic.wizards.com/en/rules) on October 27, 2026:

- [Pinned official TXT](https://media.wizards.com/2026/downloads/MagicCompRules%2020260925.txt)
- SHA-256: `8d860e451f20f38865b725b42d82feb714c725373dd8f3b32b8652b3eeb070ca`
- All **70** named keyword-action headings, rules **701.2–701.71**.
- All **194** named keyword-ability headings, rules **702.2–702.195**.
- **264** entries in source order, including the symbol heading
  **702.186, ∞ (Infinity)**. The introductions 701.1 and 702.1 are not keywords.

The independently extracted heading-only source manifest is
`testdata/keyword-reference/headings-20260925.json`. The source hash identifies
the exact bytes used for factual checking; the complete rules document is not
bundled or committed. This is complete coverage of the declared source's named
701/702 headings, not a claim to index every term ever printed on a Magic card
or every future revision. The version and scope are visible in the reference.

Variants without separate headings share their parent entry. Search aliases
include multikicker, megamorph, typecycling and basic landcycling, commander
ninjutsu, double agenda, daybound/nightbound, partner variants and the former
name totem armor. Card-specific substitutions, such as every possible
"protection from [quality]" or "partner with [card name]", do not each receive a
separate entry. Level and station symbols point to their parent mechanics;
their detailed layouts are defined by rules 711 and 721.

Ability words, such as landfall, raid, channel and rally, are labels with no
independent rules meaning (rule 207.2c); the card's following text defines the
effect. They are outside the 701/702 index. Likewise the monarch, initiative,
card types, special actions, counters and non-keyword card text have other rule
sections and are not silently counted as covered keywords. Day/night and the
Ring are summarized where the indexed keywords need them.

**Assemble (701.45)** is deliberately exceptional: the authoritative source
names it but excludes the silver-bordered Unstable mechanic's full rules. Its
entry says so and directs readers to the official Unstable FAQ instead of
inventing a complete definition. Other 701/702 headings used by optional
formats, such as planeswalking, schemes and Attractions, remain included even
when a particular match does not use that format. Playtest/acorn terminology
not defined in the pinned source is outside this reference (rule 100.7).

Chinese names and aliases are lookup aids. Common terminology was checked
against the [official Chinese keyword glossary](https://magic.wizards.com/zh-Hans/keyword-glossary).
That glossary is neither a complete 701/702 index nor a current Chinese rules
translation. Some newer or uncommon labels are descriptive, unofficial Chinese
translations; this is stated in the UI. The canonical English heading and rule
number disambiguate them. Summaries are original explanations in both languages,
not quotations of that glossary. Existing familiar alternative names and common
Traditional Chinese forms are retained as search aliases where listed.

## Content and rights

The summaries explain rules facts in original concise prose; they are not a
substitute for complete rules, Oracle text, format rules or a judge's ruling.
They intentionally omit many edge cases, which the displayed rule references
identify. Search and browsing do not provide automatic rules enforcement.

The project license applies to Hexproof's original summary text and tooling;
it does not relicense Wizards' rules or intellectual property. The reference
retains an in-app notice that it is unofficial and not approved or endorsed by
Wizards, and attributes the underlying rules to Wizards of the Coast LLC.
Magic: The Gathering is a trademark of Wizards of the Coast LLC.
©2026 Wizards of the Coast LLC. No full rules passages, card artwork, logos or
new third-party code are incorporated by this feature. See also
`THIRD-PARTY-NOTICES.md`.

## Updating the reference

Updates are reviewed source changes, never a runtime download. Use the official
rules page to find the current version, download its TXT into ignored `build/`
and record its URL, effective date and SHA-256. Compare the full affected rules,
not only their names: an unchanged heading can have changed behavior.

Extract the candidate heading index without copying the complete rules text:

```sh
python3 tools/check-keyword-reference.py --rules build/keyword-reference/MagicCompRules20260925.txt --print-headings
```

After checking added, removed, renamed and renumbered entries, update the resource
and the separately reviewed source manifest together. Keep both metadata objects
identical, preserve stable entry IDs when a rule is merely renumbered, and update
the checker's default manifest path if the manifest filename changes. Write or
revise both summaries using the authoritative rules; review Chinese labels and
aliases without presenting uncertain translations as official. Recount the
declared coverage, revise the UI notes and this specification, and refresh any
version-specific test expectations. A heading match alone does not verify a
summary's factual correctness or establish permission to copy source text.

Run offline validation plus the optional exact-source audit:

```sh
python3 tools/check-keyword-reference.py
python3 tools/check-keyword-reference.py --rules build/keyword-reference/MagicCompRules20260925.txt
python3 -m unittest discover -s tools/tests -p test_keyword_reference.py
```

The checker rejects missing, duplicated or renamed headings, changed source
identity, invalid coverage counts, absent bilingual summaries, unfinished text
and markup. The exact-source audit additionally checks the downloaded bytes and
re-extracts every heading, including Unicode headings. Ordinary tests need no
network. Client tests exercise bilingual and case-insensitive lookup, uncommon
entries, reset/no-results behavior and both integrations; native GUI verification
checks the actual layout, scrolling and input isolation.

### Native verification scenario

On the authenticated GNOME session with a usable display, build the audit client
and run both fixture modes sequentially. Each run uses an isolated profile,
starts maximized, and records search, wrapped explanations, list scrolling,
empty/reset behavior and close/focus evidence. Fixtures supply public table
projections; they do not qualify a live Forge engine match or OS input injection.

```sh
cmake -S apps/client-qt -B build/client-qt -G Ninja -DHEXPROOF_BUILD_NATIVE_AUDIT=ON
cmake --build build/client-qt --parallel 4 --target hexproof_native_audit
QT_QPA_PLATFORM=xcb python3 tools/ui-automation/run-native.py --scenario tools/ui-automation/scenarios/KeywordReference.qml --variant manual --players 1 --output build/keyword-reference/manual-new-run
QT_QPA_PLATFORM=xcb python3 tools/ui-automation/run-native.py --scenario tools/ui-automation/scenarios/KeywordReference.qml --variant forge --players 1 --output build/keyword-reference/forge-new-run
```

Use a new output directory per attempt and inspect its screenshots. A missing
monitor, unavailable session, fixture startup failure or passing offscreen tests
does not establish native GUI acceptance. Do not change the owner's desktop
configuration to make the scenario start.
