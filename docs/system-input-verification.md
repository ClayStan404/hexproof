# System-input verification

Use this guide when a change requires actual OS input routing rather than Qt
in-process test events. Select a bounded scenario under the
[development policy](development-policy.md), using the actual workstation,
maximized test windows and isolated profiles. Historical campaign results are
in Git history; this guide is not a claim about the current binary.

## Input method

`run-native.py` normally sends Qt events to an exposed native window.
`--os-input-helper tools/ui-automation/mutter-input.py` instead selects GNOME
compositor input on the workstation's XWayland display. It does not fall back
to Qt events or XSendEvent keyboard/mouse messages.

The helper requires Python `dbus`, `libX11.so.6`, `libei.so.1` and Mutter's
RemoteDesktop `ConnectToEIS` interface. These are optional test dependencies.
Other desktops/backends need their own native qualification. Supply the
workstation's authenticated display and GNOME session bus; do not change the
owner's desktop configuration to satisfy a fixture.

Input is restricted to the parent audit process's window and its verified
Qt Quick transient dialogs. The helper checks `_NET_WM_PID`, window ownership,
focus and coordinates before input. Focus-sensitive bursts are serialized
across seats. Pointer motion uses a resumed libei device with monotonic frame
timestamps; a disconnect fails the request instead of selecting another
backend. Device/session/socket cleanup runs on failure and normal exit.
Unsupported modifiers and GTK/portal choosers fail in this mode.

Drivers must focus the acting window, then re-read its current decision and
control geometry. A prompt may change during focus switching. Wait for scroll
positions to settle and targets to be fully visible; a pointer receipt alone
does not prove that a card was selected. The expected selection or resulting
game state must also match. The driver may read visible models and geometry;
this is not a computer-vision-only or physical mouse hardware qualification.

`NativeAudit` independently observes spontaneous mouse, keyboard and wheel
events on the owned window. Keyboard delivery requires a spontaneous press or
shortcut-override event and release. Pointer evidence includes actual receivers
and the mouse grabber. Successful system-input evidence requires:

- matching startup and summary records with `osInputVerified: true`;
- successful receipts for every action, with backend, PID/window, target and geometry;
- no Qt fallback, failed input or QML warning;
- the scenario's independent application/server assertions.

Screenshots contain only the owned window's rendered content, not the desktop.
For a failed pointer study, `HEXPROOF_AUDIT_EI_DEBUG=1` adds helper-local libei
logging. Receipts retain requested/observed positions, deltas, device state and
sent-frame counts for diagnosis without capturing other applications.

## Run a focused scenario

Build the audit executable and local server using
[the native scenario guide](ai-verification.md#running-the-first-scenarios).
For example, with the pinned Forge environment and an installed test catalog:

```sh
QT_QPA_PLATFORM=xcb python3 tools/ui-automation/run-native.py \
  --scenario tools/ui-automation/scenarios/LimitedLifecycle.qml \
  --freeze-scenarios --server-binary build/server/hexproof-server \
  --catalog /absolute/path/to/test-catalog/cards.sqlite \
  --fixture-dir tools/ui-automation/fixtures/limited-lifecycle \
  --players 3 --variant set_sealed-forge \
  --os-input-helper tools/ui-automation/mutter-input.py \
  --timeout 1800 --output build/system-input-sealed-new-run
```

The [Limited fixture guide](../tools/ui-automation/fixtures/limited-lifecycle/README.md)
defines the product, Cube and Forge prerequisites. Use a new output directory
for each attempt. `--freeze-scenarios` copies the drivers before launch so
later source edits cannot change a running scenario. Review screenshots and
business outcomes as well as input receipts.

## Frozen multi-format campaign

`run-os-campaign.py` is an optional broader campaign over the pinned
`tools/forge-card-corpus/decks-2026-09-22.json`: ten decks in each of Standard,
Pioneer, Modern and Legacy, plus ten cases each for Set Sealed, Set Draft and
regular Cube. These historical deck lists are versioned fixtures, not a claim
of current format legality. Resolve exact printings against the supplied
catalog and record its identity. A narrow bug fix does not require 70 games.

```sh
python3 tools/ui-automation/run-os-campaign.py \
  --output build/system-input-campaign-new-run \
  --catalog /absolute/path/to/test-catalog/cards.sqlite \
  --fixture-dir tools/ui-automation/fixtures/limited-lifecycle \
  --prepare-only
```

Inspect the plan, then remove `--prepare-only` to execute it. `--select` accepts
comma-separated case IDs for a bounded subset. Use a new `--attempt` value when
retrying; existing attempts are preserved. By default the runner skips already
passing cases and stops on failure; `--keep-going` collects independent failures.
The runner removes only its reproducible catalog copies after processes exit,
retaining profile hashes, deck state, source lists, input traces and results.

`ForgeDesktopMatch.qml` imports through production controls and delegates game
decisions to `ForgeDuelMatch.qml`. The player uses permitted visible information;
its bounded policy is not a competitive AI or proof of every card interaction.
A cast attempt is not proof that its effect resolved. Limited cases use three
players for event creation/drafting/building, then finish one assigned 1v1 game;
the third player checks the bye/free-seat projection. This does not complete a
whole Swiss tournament.

For a full campaign, validate the ledger with:

```sh
python3 tools/ui-automation/report-os-campaign.py \
  build/system-input-campaign-new-run --require-complete
```

The reporter rejects shortened/duplicate plans and rechecks both players'
natural results and system-input evidence. Failed retries never count as extra
games. If only a subset ran, report that subset and its gaps; do not claim full
campaign completion or current-release qualification from historical passes.
