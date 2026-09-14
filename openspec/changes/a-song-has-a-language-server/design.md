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

- Syntax colouring. There is no tree-sitter grammar for `.song`; vendoring
  one is a decision of its own.
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

## Risks / Trade-offs

- [The keyword tables drift from the parser] → the parser's own
  `unknown_keyword` lists are the truth and the tables are typed by hand;
  a setting the parser gains is a line to add here. Worth a test that reads
  the parser's lists, when they are exposed.
- [Full-text sync on every keystroke] → a song is a few hundred lines and
  the analysis is a lexer, a parser and an arranger over it, well under a
  millisecond; incremental sync buys nothing here.

## Open Questions

- Whether `mat` should also serve the `.song` grammar as semantic tokens,
  since it has no tree-sitter grammar and is unlikely to get one.
