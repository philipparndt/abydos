## 1. `mat pack` (musik-as-text, on its `main`)

- [x] 1.1 `mat-core/src/pack.rs`: the files a song reads from the parser, a word in the text a path when it names one of them from its file, and each placed in the pack — under the song's folder as it is, `external/` from elsewhere, `mat-samples/` from the library
- [x] 1.2 Paths rewritten only where they must be, relative to the file they are in, with the rest of the line and its ending kept; a preset that reads library samples written out
- [x] 1.3 An `.exs` of the song's own packed with its samples beside it; Apple's samples, the General MIDI bank, Surge and plugins listed in `README.txt`
- [x] 1.4 A file read and named by no word, or not there, stops the pack; the zip written to a temporary name and renamed; entries dated
- [x] 1.5 Tests: a song with a kit elsewhere, an absolute path and a library sample packs and reads only its pack when unpacked; presets; missing samples; two files of one name
- [x] 1.6 Every example packs; dream and undertow-b render byte-identical from their unpacked packs with `MAT_ASSETS` pointed at an empty folder

## 2. The pane

- [x] 2.1 `SongPack` in AbydosKit, with tests: the command line, whether a `mat` packs from its `--help`, and what it said
- [x] 2.2 *Song and Samples as ZIP* in the Export menu, disabled with a tooltip for a `mat` that cannot pack
- [x] 2.3 Asks before replacing a zip; a toast with the files, the size and what the song still needs, and Reveal in Finder
- [x] 2.4 `--song` step `pack`
- [x] 2.5 A driven run over a scratchpad copy of `dream.song`: the item in the menu, `dream.zip` written with its ten library samples, and the Logic instruments said
- [x] 2.6 `make test` and `make warnings` clean
