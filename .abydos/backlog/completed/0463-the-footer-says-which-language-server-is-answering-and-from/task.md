# 463. The footer says which language server is answering, and from where

The editor's footer already says where the caret is and what language the file
is. It says nothing about the thing actually answering questions about that file,
and it should — beside the language, which is the same fact one layer down.

**Asked for because of a real confusion.** A Rust project was pointed at an image
built on this machine, the container started, the server initialised and
answered — and from the outside it was indistinguishable from nothing having
happened. The user's words: *"it is still unclear what is used. The rust
container is selected, But I have the strong feeling that it is not used at
all."* It was being used. `container ls` knew, `lsp.log` knew, and Running
Servers knew — a window somebody has to go and open. Nowhere near the file.

## What it should say

The server's name, and **where it comes from**, since that is the half that was
missing: an installed copy, an image, or a devcontainer are three different
answers and the first is the one people assume.

Four states, and the footer needs a word for each:

- **Answering** — the ordinary case. `rust-analyzer`, and some mark for a
  container, in the way `containerMark` already marks a devcontainer pill.
- **Starting** — including a first image build, which 0459 measured at 164
  seconds. The strip above the file already says this; the footer should agree
  with it rather than invent a second vocabulary.
- **None** — a language with no server, or a file the server does not suit.
  Quiet: most files in most projects, and a footer that nags is a footer people
  stop reading.
- **Started and not working** — 0461's third state, and **that item is building
  the detection, not this one.** Take whatever it exposes; do not build a second
  way of knowing. If 0461 has not landed when this is picked up, leave room for
  it and say so rather than guessing at a design.

## Where it goes and what it costs

`EditorStatusBar` has `setPosition(line:column:)` and `setLanguage(_:)`, and the
language is already a *control* with tracking areas — so a server beside it is
the same shape rather than a new one. Clicking it should go somewhere useful:
Running Servers is the obvious target, and the tool's own settings page is the
other candidate, since that is where somebody would change the answer.

**It must cost nothing.** `setPosition` is called on every caret move, and this
draws in the same view. Whatever the footer knows has to be pushed to it when the
server's state changes — `.ideaiLanguageServersChanged` already exists and is
already posted — and never asked for while drawing.

## Worth deciding

- **Which server, when a file has several.** clangd answers for `c`, `cpp` and
  `objc`; the footer follows the *file*, so it follows the language the file is,
  which `LanguageService` already keys by.
- **A project in a devcontainer.** The pill in the titlebar already says the
  window is working inside one. Repeating it per file may be noise, or may be
  exactly right when a subproject has its own — worth a look rather than a guess.
- **Width.** A long name and a long path in a narrow editor is the same problem
  0458 hit on a card, and the answer there was to say the important part first
  and let the tail truncate.

## What it says, in the end

    sourcekit-lsp                                          1:1   Swift
    rust-analyzer ⬢ abydos-built/rust-analyzer:d409fd8bc582 1:1   Rust
    rust-analyzer ⬢                                        1:1   Rust
    rust-analyzer — fetching                               1:1   Rust
                                                           1:1   TOML

Five lines and four states. Each of them is photographed in `images/`, and the
fetching one is photographed *beside the strip*, which in the same window says
"Rust's language server is being fetched." They agree because they are the same
sentence: `LanguageServerFooter.arrivalSentence` is where it is written and the
strip now reads it from there rather than keeping a copy.

## The three things that had to be decided

**Which server, when a file's language has several.** The question turned out not
to arise, and `LanguageServers.serverKey` is why: a running server is filed under
the *server's* name and not the language's — that is 0449's "one server per
project per server, not per language" — so a `.c` and a `.cpp` in one project
both find the one `clangd` entry, and the chip says `clangd` under either. The
footer asks about the file's own language and the key turns that into the one
server that answers for it.

**A devcontainer is not repeated per file.** The chip wears the `⬢` and stops:
`rust-analyzer ⬢`, with the container's name only in the tool tip. A container is
a fact about the *window* — the titlebar pill says it and names it, and the
photograph shows the pill and the chip in one frame — so per file it would be the
same word over and over in the one place with no room for it. An image is the
other way round and is named in full: it is chosen per tool, it is written
nowhere else on screen, and *which image* is the whole of what somebody wants to
know when they wonder whether their choice took. That asymmetry is the answer to
the item's question rather than a dodge of it: the mark says "not on this
machine", which is the fact people get wrong, and the words after it say the part
that is not already on screen.

**Width.** The chip is the thing that loses. The language and the caret's
position are laid out first from the right edge and keep their places; the chip
takes what is left, and truncates at the tail — so the server's name survives and
the image tag is what turns into an ellipsis. Photographed at 1.8× zoom in a 760
point window: `rust-analyzer ⬢ abydos-built/rust-analyzer:d409fd…`. Below about
56 points the chip is dropped rather than shown as two letters and an ellipsis.

## Where the click goes, and why not the other place

**Running Servers and Containers.** Both candidates were real. The chip states a
fact about *this project* — this server, from here, now — and the questions that
follow from reading it are whether it is really running, what it is costing,
which executable the operating system resolved, and how to stop it. That window
answers all four and has the Stop beside every row. The tool's settings page is
where the answer is *changed*, but a settings page knows no project — the spec
says exactly that where it explains why a chosen server's provenance is shown in
the list and not in Settings — so a click landing there would answer a question
nobody had just asked. What is *not* built is a way from that window on to the
setting, and somebody who reads the list and decides they want a different server
still has to go and find Settings ▸ Tools themselves.

## Ruled out on the way

- **A lookup in `draw`.** Never attempted, because 0443 and 0458 both paid for
  it, but it is worth saying what the shape is instead: the footer holds two
  strings and a rectangle. `LanguageService.footer(forLanguage:project:)` is
  three dictionary lookups and the project's cached choices, it walks no
  directory and touches no `PATH`, and it is called only where the strip above
  the file is already refreshed from. `EditorViewController` compares the answer
  with the one it is holding before pushing, because
  `.ideaiLanguageServersChanged` is posted for every window's servers and a
  project opening elsewhere must not repaint every status bar in the app.
- **A word for "installed".** The chip says `sourcekit-lsp` and nothing else when
  the copy on this machine is answering. A badge saying "local" would be on
  nearly every chip in nearly every project, and the absence of a mark is already
  the statement — the `⬢` is what is worth a glyph.
- **Saying something when there is no server.** The item asked for quiet and this
  agrees with it, but the tension is real: the strip above the file is
  dismissable and ignorable, so a language somebody switched off has nothing on
  screen at all. That is the existing bargain rather than a new one, and a chip
  that nagged on most files in most projects would cost the sentence this whole
  item exists to make readable.
- **A menu on the chip, the way the language beside it has one.** The language's
  menu is a *chooser* — it changes the file — and there is nothing to choose
  here; one click going one place is worth more than a menu of two items, one of
  which is the wrong place (above).
- **Doing anything about 0461's fourth state.** Not built, deliberately.
  `LanguageServerFooter.State` has three cases and a comment saying the fourth is
  0461's to detect; a case here that nothing sets would be a design 0461 then has
  to fight. When it lands it is one case, one sentence in `arrivalSentence`'s
  neighbourhood, and no change at all to how the state reaches the bar. `git
  merge main` before this was finished brought nothing of 0461 with it — that
  item is still in `in-progress/` with none of its steps ticked.

## What the photographs did and did not show

`images/` has four states and the truncation. What is **not** proved: 0461's
fourth state, which does not exist yet; and the `— building` word, which needs a
first image build on a machine whose Docker daemon is deliberately stopped —
`abydos-built/…` names are recognised as built-here and go to the builder, which
is not running, so the wait photographed is the fetch and not the build. The
build's sentence is the strip's own, unchanged since 0459, and the chip reads it
from the same function as the other two.

One flake on the way, written down because it is nothing to do with this:
`PseudoTerminalTests.runsACommandAndCapturesOutput` failed once under a loaded
machine — 123 seconds and no output from the child — and passes in 0.03 seconds
on its own and in the whole suite on the next run. `forkpty` on a busy
multithreaded process, which is what that suite's own comment says it is. 2296
tests in 338 suites are green.

## Estimate

2026-08-11 10:41 — done

## Steps

- [x] The footer shows the server answering for the active file, beside the
      language
- [x] It says where the server came from — installed, an image, a devcontainer
- [x] Starting and none are covered, and agree with the strip's wording
- [x] 0461's "started but not working" is displayed if it has landed, and left
      room for if it has not — it had not landed, so room is left: a fourth case
      in `LanguageServerFooter.State` and nothing else
- [x] Clicking it goes somewhere useful, and the entry says which and why
- [x] Nothing is asked for while drawing; the state is pushed
- [x] Write down here what was ruled out on the way
- [x] `spec/language-servers.md` says what the project now does
