# Historical Forge evaluation

The Java bridge and probe in this directory evaluated the old Manabrew-hosted
Forge runtime. They were retired after the official native-human migration
passed local qualification on 2026-09-14. Their source remains in Git history
at commit `8da431b6`; historical results retain their original version scope.

Current official Forge rule, lifecycle and full-game tests are documented in
[the native host test guide](../../../third_party/forge-runtime/native-host/TESTING.md).
Use the real Go adapter/WebSocket suites and native Qt acceptance described in
[the migration record](../../../docs/forge-native-migration.md).

The generic laboratory workload format remains available to independent
research adapters, but there is no supported legacy Forge executable here.
