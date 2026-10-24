# Optional Forge action clock

Forge two-seat matches offer an immutable **25-minute action clock** option at
creation. This applies to ordinary rooms, server- and player-hosted rooms,
native/model AI practice, Set Sealed, Set Draft, regular Cube free play, and
constructed/Limited Swiss pairing rooms. Manual rooms, Playtest, Commander/EDH
rooms with their four-seat capacity, and Commander Cube do not offer this
option, including an EDH room that starts with only two occupied seats.

Ordinary rooms, AI practice, Limited events, and regular Cube default to off.
Constructed Forge tournaments default to on, preserving their previous timing
behavior; organizers can turn it off. Waiting rooms and event lobbies show the
server's selected setting. The table shows both remaining budgets only when
timing is enabled, and identifies the currently running player.

Each player receives 25 minutes for the **entire match**, including all games
of BO3. Time runs while a playable Forge decision is waiting for that player,
including mulligans, priority, targets, and choices. The decision owner takes
precedence over another player's priority when an effect controls a decision.
Model inference spends the model seat's budget. Native AI calculation has no
external decision boundary and is treated as engine processing time.

The clock pauses after an accepted response while Forge advances, during
sideboarding and engine startup/restart, while the player host is unavailable
or migrating, and while a model worker requires recovery. Ordinary player
connection loss does not pause a live decision. Recovery resumes the current
decision with the saved budget. Restarting the current game and advancing a
BO3 game preserve both budgets; starting a new match or returning to the
waiting room restores paused 25-minute budgets.

Reaching zero loses the entire match automatically, even without further
player input. The opponent receives the wins needed to finish BO1/BO3, and the
table publishes the timeout result. Swiss records this authoritative result
immediately; casual Cube has no standings result to record. The server owns
accounting and expiry; client interpolation is display only. Timer deadlines
are anchored to their accounting mark, and a timer from an earlier decision
or match cannot decide a later match.

`room.create.actionClockEnabled` is an optional boolean whose omission means
off. Room settings/snapshots expose the choice and enabled snapshots include
`actionClockMs`; `actionClockRunning` is absent while paused.
`tournament.create.actionClockEnabled` distinguishes omitted from explicit
false: omission retains on for Forge constructed events and off otherwise.
Tournament snapshots always publish the actual boolean, including false.
Pairing rooms inherit the event choice independently of deck locking.
