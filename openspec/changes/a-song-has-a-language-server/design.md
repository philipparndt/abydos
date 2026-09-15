## Context

A `.song` had no language: `LanguageRegistry` mapped nothing for the
extension, so a document opened as plain text with no language id, no
comment gesture and nothing for the language-server layer to look up. The
layer itself needs nothing new — a `LanguageServerDefinition` names a
command, its arguments, an install hint and root markers, and `mat` is
found through `Executables.locate` like every tool.

`mat` had no server. It has a parser with spans on every token and
diagnostics with hints (`mat check`), an arranger that resolves names, and a
preset library — everything a server answers with, in a library crate.

## Goals / Non-Goals

**Goals:**

- Diagnostics as you type, the same ones `mat check` prints.
- Completion of what a line can take, by block and by the instrument's
  kind, and of the names a song defines where a name goes.
- Hover, go-to-definition for names, the blocks as symbols.
- One binary: the renderer is the server.

**Non-Goals:**

- Syntax colouring, at first. There was no tree-sitter grammar for `.song`;
  Decision 11 wrote one when it was asked for.
- Rename, references, formatting. Names are plain words and a rename is a
  find-and-replace somebody can do; the rest has no shape yet.
- Semantic tokens, folding: the editor folds by indentation already.

## Decisions

### 1. A crate in musik-as-text, a subcommand of `mat`

`crates/mat-lsp` is a library with the analysis and the transport;
`mat lsp` is a subcommand of `mat-cli`. One binary to install and one to
find, and the server's diagnostics are, by construction, the renderer's.
*Ruled out: a separate `mat-lsp` binary.* A second thing to install, and a
second thing to be a version behind.

### 2. lsp-server, not tower-lsp

`lsp-server` (rust-analyzer's) is synchronous over crossbeam channels;
`tower-lsp` brings tokio into a CLI that has no other use for a runtime. The
server is one thread reading and one writing, and every request is answered
from a document already analysed.

### 3. Pure analysis over the text, tested without a transport

`Analysis::of(text, previous)` lexes the text into one `Line` per source
line — the lexer skips blank and comment lines, so its own vector is
re-indexed by each token's span; the first tests failed on exactly that —
parses it, and arranges the song for the name-resolution errors. When the
text does not parse, the previous song is kept, so names keep completing
while a line is half typed. `completions`, `hover`, `definition`, `symbols`
and `diagnostics` are functions of an `Analysis` and a position; `run_stdio`
only maps the protocol onto them. Twelve tests over a small song.

### 4. Completion by block, kind and word index

The block comes from the nearest header above the line, and column one is
always the top level. Inside a block, the word index on the line decides:
the first word is a setting of the block — an instrument's by its kind,
with a preset instrument taking its preset's kind — and later words are the
setting's `key=` options or the names it takes: instruments after
`instrument`, patterns after `play`, tracks after `sidechain` and `source`,
the song's layers after `layer`, presets after `preset`. The prefix under
the cursor filters server-side as well, so a client that does not is still
shown the right things.

### 5. Documentation as data

`docs.rs` is a line per keyword, taken from `docs/FORMAT.md` and shortened
for a hover; the same lines are the completion items' details. A hover on
an option shows its setting's line, which names the options; a hover on a
name shows the named block's first lines as code.

### 6. Positions are UTF-16

The parser's spans are 1-based characters; the protocol's positions are
0-based UTF-16 units. Converted through the line's text both ways, tested on
a musical symbol outside the BMP.

### 7. Exit

`Connection::handle_shutdown` consumes `shutdown` and `exit`; the writer
thread then waits for the last sender, which the connection still holds.
Found with the scripted client: the process outlived `exit` by more than
five seconds until the connection was dropped before the join.

### 8. A trusted project re-announces its open files

Found driving it: a `.song` opened before *Trust* was pressed reached no
server, and no log line said why — `LanguageService.opened` returns silently
for an untrusted project, and nothing announced the document again once the
project was trusted. The driven run opens the file at once and trusts half a
second later, which is also the order a person uses on a new project: open
something, see the strip, press Trust. `trustGranted` now rescopes the
editor, which is the same re-announcement a scope change makes.

## Driven proof

**The server on its own**, with a scripted stdio client
(`scratchpad/lsp-smoke.py`) against `mat lsp` on a song whose track says
`instrument leed`:

| Asked | Answered |
| --- | --- |
| initialize | `completionProvider`, `definitionProvider`, `documentSymbolProvider`, `hoverProvider`, `textDocumentSync` |
| didOpen | one diagnostic at line 9 character 13, `unknown instrument 'leed'` |
| completion after `instrument ` | `lead` |
| completion on a synth's line | `osc`, `noise`, `filter`, `amp`, `fenv`, `vibrato`, … |
| hover on `osc` | `**osc** — An oscillator: …` |
| definition of `verse` in `play verse` | line 5 character 8 |
| documentSymbol | `lead` (class), `verse` (array), `melody` (function) |
| shutdown, exit | exited in 0.1 s — after Decision 7; before it, never |

**In the app**, on a copy of `drunken-sailor.song` with line 137 changed to
`instrument brasss`, `mat` on the run's PATH, 2026-09-14:

| Run | Report |
| --- | --- |
| `--diagnostics 6,10` | `137: error drawn as error — unknown instrument 'brasss' / did you mean 'brass'?`, at six seconds and still at ten |
| `--definition 127:15` (`instrument choir` in `track pad`) | the caret at line 17, `instrument choir synth` |
| the same file before Decision 8 | `servers=[]`, and the log's only line `no song server for songs: definition unanswered` |
| `~/.cargo/bin/mat` from the day before, without `lsp` | the banner `mat is not running for this project`, and the log `unrecognized subcommand 'lsp'` — the install hint is the fix, and the installed copy was rebuilt |

The capture shows `mat` named in the footer as the song's server and the
language as *Song*, beside the song pane showing its own failure for the
same mistake — the file was broken before it was first rendered, so there
was no last good render to keep playing.

### 9. Where each line is heard, beside its number

*Added 2026-09-14.* `mat lsp` sends `mat/timeline` after each analysis that
parses: the song's length, its bar length, and per line the stretches, in
seconds, where it is heard. A notification rather than a request, so it
arrives with the diagnostics for the same text; withheld when the text does not
parse, because lines placed from the last song that did would be drawn beside
lines that have since moved. The pass that computes it lives beside `arrange`
rather than in it: `arrange`'s timeline is what the render cache hashes, and a
source line in it would invalidate every layer when a comment is added.

The gutter draws a column of bars between the breakpoint strip and the numbers,
only while the file has a timeline: a faint bar the song's length, lit where the
line is heard, nothing on a line heard nowhere. Hover says `bars 3–4 ·
0:04.000–0:08.000`, or `2 times: bars …` for more than one stretch.

Driven on a copy of the shanty (`timeline:<line>`): `pattern verse` lit at
0.108–0.324 and 0.541–0.757 of the song, "2 times: bars 5–12, 21–28"; its first
line "bars 5–6, 21–22"; the first `play verse` "bars 5–12 · 0:07.272–0:21.818";
`track drums` the whole song; an `osc` line nothing. The capture shows the
gallop patterns lit nearly across, and each verse line as two short dashes.

The playhead is a tick through every bar, a caret-coloured line a little taller
than the bar, redrawn only when it moves a whole pixel. A click on a bar seeks
the pane to the time under the pointer and a drag scrubs; the bar is the song's
timeline length, which ends at the last bar, so the render's tail is not on it.
Driven on the shanty (`timeline-click:<line>:<fraction>[:<to>]`), 2026-09-15:
paused at 10 s the tick at pixel 8; a click at 0.5 on `track drums` put the
playhead at 33.64 s, half of 67.27; a drag from 0.1 to 0.25 at 16.82 s; a click
on a blank line left it there; playing moved the tick on.

### 10. Time codes, hidden as blame is, and a song as a program being debugged

*Added 2026-09-15.* Asked: "maybe we should show the time code, and make the
sections able to show and hide like git blame", and "while playing would be
nice to also have the debugger markers (multiple in that case) and support for
breakpoints".

A time-code column sits left of the bars: where the line is first heard. A click
goes to the next time the line is heard after the playhead, or back to the
first, so a pattern's repeats are walked by clicking again. Both columns are
settings (`songTimeCodes`, `songTimelineBars`, on by default), toggled from the
gutter's right-click menu beside *Show Blame* and from the Editor menu, and
applied to every group as word wrap is.

While the pane plays, the lines heard at the playhead get the debugger's
stopped-line band, lighter since several move at once; a stretch holds its
start and not its end, so a bar's line and the next bar's are never both marked
on the boundary. The breakpoints are the gutter's own — made by clicking a
number, kept by the debug coordinator as for any file — and the pane asks, on
each tick, for the earliest enabled breakpoint whose line starts between the
last tick and this one. It pauses, seeks back to that moment exactly, and marks
the line as stopped. A start exactly at the last tick is not reached, which is
what lets play go on from a breakpoint; a seek resets the last tick, so jumping
past a breakpoint does not stop on it. A tick is a thirtieth of a second, so up
to that much past the breakpoint has been heard before it stops. A breakpoint on
a line first heard at 0:00 stops only when a loop comes back round to it.

The breakpoint tag starts right of the song's columns, not under them.

Then: "it would be very cool to highlight the current pattern part while
playing". mat ecdd911 keeps on each pattern event the character it is written
at, and `mat/timeline` gives a pattern's line `passes` — where each pass of the
pattern starts — and `notes`, each `[start, end, from, to]` in seconds from a
pass and 0-based UTF-16 columns. One list of notes serves every pass because a
song has one tempo, which keeps the message the size of the text rather than of
the song. The editor finds the last pass started by the playhead, and the one
before for a note ringing into the next, and lights the notes it is inside; a
chord is one note, a grid row one per cell. Then: "the highlighting should be a
different color so that it differs from the selection and should also be
visible when the range is selected". The first cut was a band in the git marks'
blue, drawn before the line, so it read as a selection and a selection covered
it. It is now amber, a translucent fill with a solid outline, painted in
`drawLine` after the selection as the current search match is; captured with
lines 50–58 selected over a song stopped at 0:07.272, the chord and `A4:q`
inside the selection and the grid cells outside it are all plainly lit.
Only the rows whose marks changed are redrawn.

Driven on the shanty, 2026-09-15:

| Step | Report |
| --- | --- |
| breakpoint on `A4:q A4:e …` (line 56), seek 0:05, play | paused at 0:07.272, `stopped=56`; heard there: `pattern verse`, line 56, the first `play verse`, `track melody` and the bars ending at 7.27 no longer; lit notes `56:2-6` (`A4:q`), `51:2-14` (the chord), `41:5-6` (a gallop cell) |
| play on | not stopped again; 0.6 s later `56:20-24`, then `56:38-40`, `56:41-43` |
| a grid row (line 41) | 12 notes over 24 passes, one cell lit at a time |
| time code of the first `play verse` | playhead 0:07.272 (reported 0:08.158 while playing on) |
| time code of line 56, twice | 0:36.36 — the second pass — then 0:07.272 again |
| hide time codes, hide bars, show both | gutter 192 → 122 → 88 → 192 points |

Found driving it: a seek lands on a whole sample just before the moment asked
for, so the song stopped at 7.2727 s read 7.27270 minus a sample. The marks
at the stop were the bar before's, and play would have stopped on the same
breakpoint at once; `LineTimeline.slack`, two milliseconds, is the fix.

### 11. A grammar, kept by musik-as-text and vendored here

*Added 2026-09-15.* Asked: "and we definitly need syntax highlighting". The
grammar lives in musik-as-text as `tree-sitter-song/` (mat d333880): written
from the parser's keyword lists, no external scanner, ABI 15, lenient — an
unknown word on a body line is a word and not an error, so a half-typed line
does not turn the rest of the file red. All 29 `.song` files in that repository
parse with no error node, and its corpus has 36 cases. Here it is the sixth
vendored grammar, `TreeSitterSongVendored`, copied as generated, because its
only upstream is mat itself; `vendor-grammars.sh` leaves it alone.

Headers and `play` are keywords, defined names functions, instrument kinds
types, setting names and option keys properties, notes and drums constants, a
rest a builtin, durations attributes, velocity a label, grid hits strings,
names where they are used variables. *Ruled out: semantic tokens from
`mat lsp`.* Abydos colours from tree-sitter, not from servers, so a server's
tokens would have been a second colouring path for one language, and a grammar
also serves every other editor mat is written in.

`SongLanguageTests.aSongIsColoured` asks the engine; the capture of the shanty
playing shows it coloured, with the notes under the playhead lit.

### 12. Includes: a song of several files

*Added 2026-09-15.* Asked: "and we should support includes". mat e72d7e5
reads `include "kit.song"` as though the file were written at that line, a
file included twice once, relative to the file the line is in; ce7deec gives
the grammar the statement. `mat lsp` sends a `mat/timeline` for every file of
the song, each with its own lines and with `song` and `files`, and every line a
track names carries its file. An included file opened alone is analysed
through the song that includes it — an open one first, the workspace's
`*.song` otherwise. The render's manifest names its `sources`.

In Abydos:

- **A save of any source renders again.** The pane fingerprints every file the
  last render read and watches each one's directory, none inside another; a
  new pane on a song kept in the cache knows its sources before its first
  render.
- **The playhead reaches the included files' tabs.** The song's pane marks its
  own tab and posts the news; every editor group lights the tabs whose
  timeline names this song. The pane's own drawing still stops while it is out
  of sight, but the marks and the breakpoints go on — an included file's tab
  in front is exactly when they are wanted.
- **Breakpoints in any file stop the song**, each placed by its own file's
  timeline, whether the file is open or not; the earliest reached wins.
- **The debugger's frames are in their files**: a pattern in the kit is two
  frames in `kit.song` under `play beat x14` and `track drums` in `song.song`.
- **An included file's own pane does not drive the song.** Found driving it:
  `kit.song` opened beside the song has a pane of its own, silent, and it told
  every file of the song the playhead was at 0 over the song's 4.35. A tab
  whose timeline names another song is marked by that song's pane only.

Driven on a copy of mat's `examples/include` (`song.song` including `kit.song`
and `parts/bass.song`), with `open:kit.song` in front, 2026-09-15:

| Step | Report |
| --- | --- |
| `timeline:13` on the kit | `song=song.song files=3`, the clap row "14 times: bars 3, 4, 5, …", first at 0:04.354 |
| breakpoint on the kit's line 13, play | stopped at 0:04.354; the kit tab `playhead=4.35 stopped=13`, lines 3, 11–15 heard, a cell lit on rows 12–14 |
| the debugger | `beat: x@kit.song:13 > beat: x@kit.song:14 > pattern beat · pass 1 of 14@kit.song:11 > play beat x14@song.song:24 > track drums@song.song:20` |
| line 1 of the kit edited on disk | `runs=2` — the song rendered again |

## Risks / Trade-offs

- [The keyword tables drift from the parser] → the parser's own
  `unknown_keyword` lists are the truth and the tables are typed by hand;
  a setting the parser gains is a line to add here. Worth a test that reads
  the parser's lists, when they are exposed.
- [An included file's own pane] → it renders the file alone, which has no
  tracks and is silent. It should show the song that includes it; not done.
- [Full-text sync on every keystroke] → a song is a few hundred lines and
  the analysis is a lexer, a parser and an arranger over it, well under a
  millisecond; incremental sync buys nothing here.

## Open Questions

- None open: semantic tokens were answered by Decision 11.
