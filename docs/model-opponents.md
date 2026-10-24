# Local and online model opponents (experimental)

## Scope and setup

Local and online model opponents are experimental. Model responses can fail and
pause a game; reliable full-game play with real models has not been verified.
This status does not change native Forge AI or its existing three presets.

Model practice uses the existing Forge rules mode, with one human and one
room-owned model seat in ordinary constructed BO1. Both server-hosted and
player-hosted Forge are supported. The desktop makes model requests in either
case; a hub never connects to the player's localhost or stores their API key.
Native Forge AI remains a separate opponent.
Hybrid scripted/model policies and managed model-worker services are outside
this implementation; the earlier proposals are not an automatic work queue.

Configure a local or online connection in Settings, then select that source
when creating a Forge room. Each connection has a base API URL, model name,
request timeout, output limit and game budget. Local Ollama and LM Studio use
their OpenAI-compatible `/v1/chat/completions` interface. Online providers must
implement that interface over HTTPS. This slice does not add native Anthropic,
Ollama chat, or OpenAI Responses transports.

Start the model service and load a model before testing the connection. Typical
base URLs are `http://localhost:11434/v1` for Ollama and
`http://localhost:1234/v1` for LM Studio; use the actual address and model
identifier reported by that service. Enter the base URL, not the full
`/chat/completions` path. Hexproof does not download model weights or launch
either inference service.
Provider interface references: [Ollama](https://docs.ollama.com/api/openai-compatibility),
[LM Studio](https://lmstudio.ai/docs/developer/openai-compat/chat-completions) and
[OpenAI Chat Completions](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create).

Defaults are a 60-second request timeout, 200 requests per game, 1,024 output
tokens per request and a conservative 500,000-token game allowance. The local
profile uses `max_tokens`; the online profile uses `max_completion_tokens`.
Choose the parameter accepted by the provider, then save and test. Saving an
empty API-key field removes the key for that session; re-enter it when editing
a profile that needs authentication.

The connection test submits a small synthetic decision and checks the returned
choice. It does not send a real deck or certify playing strength. The selected
model must support JSON-object output and the configured completion-token
parameter. A successful test is not proof of reliable play across all prompts.
Models have no calibrated difficulty tiers; changing the model or thinking
budget does not promise a particular strength.

The human selects their own deck and the model's deck independently in the
waiting room. Configuration changes clear human readiness. Controller/source
changes require a new room, and model profile edits apply to a later connection.
During a game the table exposes waiting, thinking and paused states; waiting
and thinking give their line to an open decision, while a paused model stays
visible with its recovery controls. A failed
decision can be explicitly retried; ordinary concession and leaving remain
available. There is no silent native-AI takeover or automatic online fallback.
To replace an active connection or key, open model settings, disconnect the
worker, save the profile, then return to the table and retry. That explicit retry
authorizes the updated connection for the same source and current room.

## Ownership and privacy

The hub owns the model seat. It has no human connection, never becomes host,
does not wait for artwork, and cannot retain an abandoned room. The engine
creates that seat with the existing human-compatible native decision controller,
while room metadata marks it `modelAi`. Native Forge AI still uses `forgeAi`.
No native adapter revision is required for model decisions.

The desktop model worker is a separate C++ service and WebSocket role. It uses
a room-scoped random capability delivered privately to the human host, distinct
from human-seat authority and the privileged Forge hosting capability. It cannot
send normal room commands. Its messages never become ordinary player snapshots,
game logs or spectator publications.

Each decision contains the model seat's normalized snapshot and current typed
prompt. That observation includes its own hand and legitimately visible choices;
it excludes the opponent's private cards, unknown library order, chat, raw Forge
actions and host publications. The desktop may enrich visible card identities
with rules text from its installed catalog. It cannot query an unknown opponent
card through the model interface. Model output has no shell, file, general tool
or arbitrary network capability.
Decisions are stateless: this version sends the current permitted view and
prompt, without a conversation history or a separate memory of earlier reveals.

The endpoint and model configuration stay in a desktop-local profile. API keys
are held only in memory for the application session, never written to the
profile, command line, hub, diagnostics or model input. Choosing an online
profile explicitly sends the permitted AI observation, including its hand, to
that configured service. HTTP redirects are rejected. A local URL may itself
proxy a cloud service, so selecting Local does not certify offline inference.

The desktop owner can inspect their worker's memory and therefore the model
seat's private hand. This is trusted practice, not an anti-cheat boundary against
that owner. The normal human table still receives its ordinary redacted view.

## Decisions, limits and recovery

The hub captures an immutable decision under the room operation lock. HTTP
inference runs asynchronously on the desktop and holds no room lock. A returned
answer must still match the authorized worker, game, request and current prompt.
The existing typed rules validator reconstructs the canonical Forge response;
Forge remains the authority on game legality. No generated game-state mutation
or free-form command is executed.

Only unambiguous acknowledgements and qualified forced decisions are handled
without inference. Every meaningful choice goes to the configured model.
Model output must be a structured `RulesRespond` object for the current prompt.
The system message supplies the response shape for that specific prompt.
Structured decisions use the top-level response ID `$submit`; candidate IDs
belong only in their corresponding selection fields. The model still receives
all legal candidates and chooses among them; the response shape does not suggest
a preferred action.
Invalid JSON or a rejected answer gets at most one bounded repair attempt.
Further rejection, timeout, refusal, exhausted budget or a connection failure
pauses the opponent. Error messages use controlled categories and do not echo
private prompts, provider response bodies or credentials.

There is at most one model request in flight. Per-decision time, output tokens,
per-game requests and a conservative total token allowance are bounded. Input
bytes plus the maximum output allowance are reserved before each HTTP attempt,
including repairs. This is conservative accounting, not a price guarantee.
Retrying, reconnecting or editing a profile in the same application process does
not replenish the current game's model budget. These counters are held in
memory; restarting the application starts fresh counters. They are not a
provider-side spending limit.
Oversized observations fail explicitly instead of silently dropping legal
candidates. Cancellation invalidates late replies; it cannot guarantee that a
remote provider stops computation or billing.

Departure, game replacement, terminal results and capability replacement revoke
pending work. Worker disconnect pauses the model; reconnect can recover the
current decision. Initial worker connection failures also expose local pause and
retry while the human room connection stays open; a delayed hub waiting status
does not conceal that local failure. An explicit retry creates a fresh request
identity, so an old reply cannot act twice. No hidden state is revealed to the human as a recovery
shortcut.

## Protocol

`room.create.aiSource` is `forge`, `local` or `online`. Existing requests with
only `aiDifficulty` still select native Forge AI. Only native AI accepts a
difficulty. `room.ai.configure` accepts the model deck without a difficulty.
Room discovery and snapshots expose only source/controller metadata.

`room.ai.worker` is the private host grant; `room.ai.status` carries public
waiting/thinking/paused state and a controlled error code. `room.ai.retry` is a
host-only recovery command. A separate socket to the existing WebSocket endpoint
with `ai=1` accepts `ai.attach`, then
exchanges `ai.decision`, `ai.answer`, `ai.rejected`, `ai.failure` and `ai.cancel`.
Canonical fields and fixtures are in `protocol/v2/payload-model-ai.json` and
`testdata/protocol/v2/`. No endpoint or credential is part of the decision wire
contract.

## Verification

Select checks under [development-policy.md](development-policy.md). Focused
tests cover private observations, worker/normal-role isolation, stale and
duplicate answers, bounded repair, timeout, retry, host reconnection with token
rotation and room cleanup. The TCP handshake-failure fixture checks local
pause, delayed hub status, explicit retry and rejection of stale notifications
while the human socket remains connected.

Backend commands, run from `apps/server`, include:

```sh
go vet ./... && go test ./...
go test -race ./internal/room ./internal/server ./internal/protocol
go test -tags engineintegration ./internal/server -run '^TestLiveModelAIPractice$' -count=1 -v
```

Set `HEXPROOF_REAL_FORGE_ROOT` to the absolute path of the matching extracted
runtime before the opt-in engine test. It uses a deterministic typed-decision
worker to verify the production worker-to-hub-to-Forge path; it does not qualify
real-model quality or provider compatibility.

Desktop validation uses isolated profiles, maximized X11 windows and production
Qt controls on the workstation. The loopback-only
`tools/ui-automation/model-endpoint-fixture.py` serves deterministic Chat
Completions replies. Start it with a fresh `--output` directory and
`--reject-first-decision`, then pass its printed base URL as
`HEXPROOF_AUDIT_MODEL_ENDPOINT` to `run-native.py` with
`--scenario tools/ui-automation/scenarios/ForgeDesktopMatch.qml`,
`--variant model-local`, `--players 1`, the Forge AI deck fixture, installed
catalog and isolated card-art fixture. Add `--player-hosted` and the installed
`HEXPROOF_FORGE_HOST_RUNTIME_DIR` for creator hosting. Server hosting uses
`HEXPROOF_FORGE_HARNESS` and `HEXPROOF_FORGE_HOME` as in other native Forge checks.

For an explicitly authorized live-provider check, use the same
`ForgeDesktopMatch.qml` scenario with `--variant model-online`, `--players 1`,
`--deck-manifest tools/ui-automation/fixtures/forge-ai.json`, installed catalog
and art, and an isolated local Forge hub. Set `HEXPROOF_AUDIT_CLAUDE_SETTINGS`
to an absolute existing settings-file path and `HEXPROOF_AUDIT_MODEL_NAME` to
the exact provider model identifier. The scenario reads that file's
`env.ANTHROPIC_BASE_URL` and `env.ANTHROPIC_AUTH_TOKEN`; the gateway must expose
the supported OpenAI-compatible Chat Completions interface over HTTPS despite
those setting names. Only the path enters the runner environment, not the key.
It configures the profile through production controls; credentials stay out of
arguments, evidence and persisted profiles. Never publish the settings file.

Record provider, source/runtime and scenario identity with the actual result.
A live-model pause fails the run instead of silently retrying until it passes.
Provider connectivity, deterministic-fixture completion and real-model game
completion are separate outcomes, and none certifies calibrated playing
strength. Historical execution records remain in Git; they do not qualify a
new model, provider configuration or source revision.
