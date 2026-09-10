# jMagic actual supported-toolchain execution

Pin: `40e573f8e6d1cf42603fd05928f42e7080ce0f0d`,
<https://github.com/jmagicdev/jmagic>. A fresh local checkout was built with
OpenJDK 8 and its declared Maven reactor, with no source or rule changes:

```sh
python3 tools/engine-eval/capture.py \
  --output build/jmagic-evidence --name jdk8-integration --timeout 900 \
  --cwd /absolute/pinned/jmagic -- \
  env JAVA_HOME=/usr/lib/jvm/java-8-openjdk MAVEN_OPTS=-Xmx2g \
  mvn -B -ntp -T 2 -pl engine-integration-tests -am test
```

The JDK path above is the verified Arch evaluation environment, not a portable
installation instruction. Preserve the machine's default Java. Maven resolves
the upstream POM dependencies; no vendor runtime installer is required.

The 2026-09-09 run reported 342 test cases: **337 passed, 5 skipped, no failures
or errors**. Inspect the actual Surefire XML rather than the build exit alone:

```sh
python3 tools/engine-eval/upstream_report.py \
  --root /absolute/pinned/jmagic/engine-integration-tests/target/surefire-reports \
  --glob 'TEST-*.xml' --output build/jmagic-upstream.json
```

The executed tests include multiplayer, double-faced cards, priority, combat,
countering, triggers, replacement, and object-visibility scenarios. For example,
`ObjectVisibilityTest.crownOfConvergence` casts real cards, pays with real mana
abilities and checks changing library-top visibility. These are upstream
fixtures, **not** all seventeen frozen Hexproof scenarios, a modern-card catalog
qualification, a network redaction certification, or a benchmark. A successful
2014 codebase is not disqualified merely by its age; the maintenance/card gap
and missing explicit source-license grant remain distinct adoption concerns.

Evidence: `build/engine-thorough-20260909-pcbfuvZp/jmagic-build/command-iuww3wtl/`;
source: sibling `jmagic/`. The selected reactor builds the engine/cards/testing
modules, not the GUI distribution. No public game-finder service was contacted.
