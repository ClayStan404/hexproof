# Operation sound effects

Short, restrained tabletop cues bundled offline with Hexproof. Source recordings
are published under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/),
except the CC BY 3.0 turn cue and the owner-provided cast/resolve recordings
whose licenses were not specified in the supplied files.
The client embeds mono, 44.1 kHz, 16-bit PCM WAV files for preloaded
`QSoundEffect` playback; it never downloads audio during a game.

## Sources and notices

- [Casino Audio 1.1](https://kenney.nl/assets/casino-audio), Kenney:
  paper/card handling. Original notice: `Kenney-Casino-License.txt`.
- [Interface Sounds 1.0](https://kenney.nl/assets/interface-sounds), Kenney:
  short confirmation, cancellation, error, and glass accents.
  Original notice: `Kenney-Interface-License.txt`.
- [Impact Sounds 1.0](https://kenney.nl/assets/impact-sounds), Kenney:
  soft impact and wood contact. Original notice: `Kenney-Impact-License.txt`.
- [Magic Spell SFX](https://opengameart.org/content/magic-spell-sfx),
  JaggedStone, published October 17, 2014: `magical_1_0.ogg` and `magical_2.ogg`.
  The source page specifies CC0 and no required attribution. These were the
  previous cast/resolve recordings, replaced by the owner's files below.
- Owner-provided `cast.wav` and `Accept.mp3`, supplied in the repository root,
  replace the cast and resolve cues respectively. The supplied files do not
  identify their authors or redistribution licenses; they are not covered by
  the CC0 default or the source code license.
- [UI Decline or Back](https://opengameart.org/content/ui-decline-or-back),
  David Mckee (ViRiX), published June 18, 2012: `Decline.wav`, licensed under
  [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/), used for `turn.wav`.
  Attribution requested by the author:

  > Some of the sounds in this project were created by David Mckee (ViRiX)
  > soundcloud.com/virix

  Author profile: [soundcloud.com/virix](https://soundcloud.com/virix).

Hexproof modifies these recordings by trimming, filtering, fading, adjusting
levels, and mixing the attack/block layers. The replacement cast/resolve cues
preserve every decoded frame, with stereo-to-mono PCM16 conversion and peak
normalization to -11/-12 dBFS respectively; they are not trimmed or filtered.
The turn cue preserves the complete
3.204-second source, including its quiet tail, with mono conversion, a 25 ms
fade-out, and normalization to a -12 dBFS peak. Source links,
archive member names, SHA-256 hashes, layer gains, processing steps, durations,
and output hashes are recorded in `manifest.json`. Preserve this provenance when
replacing a cue. Per-cue license and processing fields override manifest defaults.
These are edited recordings, not AI-generated audio.

## Cue vocabulary

| Cue | Intended feedback |
| --- | --- |
| `click`, `select` | Explicit UI or card selection |
| `draw`, `play`, `tap`, `shuffle` | Card handling |
| `attack`, `block` | Combat pair assignment |
| `cast`, `resolve` | Spell/ability decisions |
| `turn` | The local player's new turn |
| `damage` | Public life loss or explicit life adjustment |
| `confirm`, `cancel`, `error` | Decision feedback |

Clips last 0.06–3.21 seconds and peak between -14 and -9 dBFS before the
user's volume control. The default playback level is 35%. Operation cues do not
loop and there are no hover or pointer-follow sounds. Background music
has its own controls and provenance in `../music/`.
