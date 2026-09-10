#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Hexproof contributors

set -euo pipefail

source_dir="$1"
protocol_mode="$2"
cd "${source_dir}"

if [[ "${protocol_mode}" == regenerate ]]; then
    cargo run --locked -q -p manabrew-relay-protocol --bin gen-protocol -- src/protocol
elif [[ "${protocol_mode}" != bundled ]]; then
    printf 'Expected regenerate or bundled protocol mode.\n' >&2
    exit 1
fi
node scripts/gen-harness-prompts.mjs forge-harness/src/main/java

# Resolve the dependency list in the SAME reactor as package. The harness is
# last, so its complete resolved graph replaces the earlier module reports.
# Pin the inspection plugin to the version already declared by upstream.
mkdir -p target
mvn -B -pl forge-harness -am package \
    org.apache.maven.plugins:maven-dependency-plugin:3.1.2:list \
    -DskipTests -DincludeScope=runtime -DoutputAbsoluteArtifactFilename=true \
    -DoutputFile="${source_dir}/target/hexproof-runtime-dependencies.txt" \
    -DappendOutput=false -Dsort=true
if grep -q 'xmlpull:xmlpull:' target/hexproof-runtime-dependencies.txt ||
        ! grep -q 'forge:hexproof-xmlpull-api:jar:' target/hexproof-runtime-dependencies.txt; then
    printf 'The harness must use the source-built XMLPull API, without the old binary.\n' >&2
    exit 1
fi

regression_classpath="forge-harness/target/test-classes:forge-harness/target/forge-harness-jar-with-dependencies.jar"
mkdir -p target/hexproof-regression-profile
for regression_class in \
    forge.harness.host.ManaBrewEngineAdapterTest \
    forge.harness.host.InteractiveSnapshotExtractorTest \
    forge.harness.common.HarnessPlayPlumbingTest; do
    java -Djava.awt.headless=true -Duser.home="${source_dir}/target/hexproof-regression-profile" \
        -cp "${regression_classpath}" "${regression_class}"
done
node scripts/harness.mjs update-checksum
node scripts/harness.mjs stage
