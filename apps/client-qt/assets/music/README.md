# Background music

The client streams bundled tracks with `QMediaPlayer` and loops the selected
track from application startup until exit, including menus, waiting rooms,
settings, and manual or Forge matches. The audio settings page has independent
music mute, volume, and track selection; defaults are enabled, 20%, and Gitana.
Saved preferences are applied before playback starts. Navigation, entering or
leaving a match, and reconnects do not interrupt or restart the track.

The selectable tracks are Gitana, BGM 2, and BGM 3. `Gitana.mp3` is the
unmodified file supplied by the project owner from their Downloads directory;
`bgm2.ogg` and `bgm3.ogg` are unmodified Ogg Vorbis files supplied in the
repository root. Their authors and redistribution licenses were not specified
in the supplied files. Do not infer CC0 or GPL coverage from neighboring assets.
`manifest.json` records each exact hash and original format provenance.

To add an owner-selected track, preserve its source and license here, add the
asset to `HEXPROOF_MUSIC_FILES` in the client CMake file, and add its stable ID,
display title, and resource URL to `BackgroundMusicController`'s catalog. The
settings selector reads this catalog; no additional selector code is needed.
