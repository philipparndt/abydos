## Why

Asked for on 2026-09-21: "export everything (samples + text model to one zip
file)", and then "the sample locations need to be updated in that case as well
in the text. It should get one self contianing archive".

A song is rarely one file. `examples/neon.song` takes ten samples from `mat`'s
library through its `house-kit` preset; a song of somebody's own names its
samples beside it, in a kit folder elsewhere, or by an absolute path, and
includes files from other folders. Handing one on means finding every file it
reads, and then its paths are wrong wherever it lands.

Which files a song reads is `mat`'s knowledge: it is the reading its render
makes, presets, includes and library prefixes and all. So the pack is `mat`'s to
make, and the pane asks for it.

## What Changes

- **In musik-as-text (`mat`), on its `main`:** `mat pack <song> -o <zip>`
  (faece3d, caacf43). One folder named after the song: the song, its includes,
  its samples and audio, its own `.exs` instruments with their samples, and the
  library samples it uses. The paths in its text point into the pack — a file
  from outside the song's folder in `external/`, a library sample in
  `mat-samples/` — and only a path that has to change is changed. A preset that
  reads library samples is written out in the song. What comes with installed
  software — Logic's and GarageBand's libraries, the General MIDI bank, Surge,
  Audio Unit and CLAP plugins — is left as written and listed in the pack's
  `README.txt`, as chosen on 2026-09-21: Apple's sample content is not the
  song's to hand on. A missing sample stops the pack, with where it is named.
- **The song pane's Export menu** gains *Song and Samples as ZIP*: `neon.zip`
  beside `neon.song`, asking before it replaces one, and a toast saying how many
  files and what the song still needs installed where it is played.
- **Offered only by a `mat` that packs**, asked of `mat --help`; an older one
  leaves the item off with a tooltip saying to update it.

## Impact

- `Sources/AbydosKit/Preview/SongPack.swift` (new): the command line, the
  question of `mat --help`, and the reading of what `mat pack` says.
- `Sources/AbydosApp/Editor/SongPreviewView+Export.swift`: the menu item and
  `pack`, and the running of an export shared between the two.
- `MainWindowController+Audio.swift`: a `pack` step for driven runs.
