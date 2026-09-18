# Previews

## ADDED Requirements

### Requirement: A song's files are edited in the song's own tab

A tab showing a song SHALL show any of the files that song is made of, in
place: the text in front SHALL change and the song's pane SHALL NOT — it SHALL
go on playing and rendering what it was, without being asked again which song
anything belongs to. Each file SHALL keep its own caret, folds, scroll and
undo across such a change. Opening one of a song's files SHALL show it in that
song's tab rather than opening another tab, whether it is opened from the
project tree, by following a definition, or by a driven step. Moving between a
song's files SHALL be recorded as navigation, so the history walks back through
it. A file no open song is made of SHALL open as itself, as any file does.

Above the text a song's tab SHALL say which of the song's files is in front:
the song's name, a menu of every file the song is made of with the one in front
marked, and the path to it. Choosing a file from that menu SHALL show it. A tab
that is not a song's SHALL show no such row.

Asked for 2026-09-16.

#### Scenario: walking into a song's files while it plays

- **GIVEN** the drive example playing, rendered once
- **WHEN** `drums.song` and then `parts/bass.song` are opened, and then the song
- **THEN** there is one tab throughout, the pane never stops and never renders
  again, the playhead only moves forward, and the row above the text names the
  song with the file in front beside it

#### Scenario: a file no song claims

- **GIVEN** a file of patterns that no open song includes
- **WHEN** it is opened
- **THEN** it opens as its own tab, and nothing asks which song it belongs to

### Requirement: A jump that finds nothing says so

Following a definition that the language server answers nothing for SHALL say
so, rather than leaving the editor where it was with no sign that anything was
asked.

Asked for 2026-09-16, of a server that answered every name asked of it and
nothing for the keyword beside them: "it seems not be possible to navigate to
includes and functions - do we miss a navigation feature in the LSP?"

#### Scenario: nothing under the caret

- **GIVEN** the caret on a word the server has no definition for
- **WHEN** a definition is asked for
- **THEN** the editor says no definition was found, and stays where it is
