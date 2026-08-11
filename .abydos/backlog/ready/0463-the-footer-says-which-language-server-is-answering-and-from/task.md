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

## Steps

- [ ] The footer shows the server answering for the active file, beside the
      language
- [ ] It says where the server came from — installed, an image, a devcontainer
- [ ] Starting and none are covered, and agree with the strip's wording
- [ ] 0461's "started but not working" is displayed if it has landed, and left
      room for if it has not
- [ ] Clicking it goes somewhere useful, and the entry says which and why
- [ ] Nothing is asked for while drawing; the state is pushed
- [ ] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says what the project now does
