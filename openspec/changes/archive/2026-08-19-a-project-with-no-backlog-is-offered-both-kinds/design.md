## Context

`BacklogAbsentView` is one view with one button. It is built once in
`BacklogPane.build()`, shown by `showContent()` whenever `hasBacklog` and
`hasOpenSpec` are both false, and its `onMake` runs `confirmMakeBacklog()` — a
sheet naming the assistants installed on this machine, then `BacklogSetup.run`.
Everything about that path stays.

What the pane knows about OpenSpec is already there and is read-only:
`OpenSpec.exists`, the changes on disk, `OpenSpec.commandLine()` — which is
`Executables.locate("openspec")`, the login-shell search, because on this
machine the CLI sits under an fnm multishell directory with a shell's PID in its
name — and `OpenSpec.installHint`. What it does not have is a way to *make* an
`openspec/`.

`FileNoticeView` is the shape the report asks for: `NSImageView` at 40 points, a
15-point semibold title, a 12-point detail line, then an `NSStackView` of
`NoticeButton`s, the lot centred in the view. `NoticeButton` is a flat themed
`NSButton` subclass, `private` to that file, drawing an SF Symbol beside a
label and tracking hover.

Two facts about `openspec init` decide most of this design. It is interactive —
`--tools` exists precisely so that it need not be, and its values are
`all`, `none` or a list of two dozen assistant names — and what it writes is
slash commands and skills into the repository for whichever of those were
chosen.

## Goals / Non-Goals

**Goals:**

- A project with neither record is offered both, in one view.
- The empty state and the editor's file notice are visibly the same design, and
  share the button that makes them so.
- Setting up OpenSpec is the real `openspec init`, with its questions asked of
  the person rather than answered for them.
- A machine without the CLI is told, in the view, before the button is pressed.

**Non-Goals:**

- Re-implementing `openspec init`.
- Choosing assistants for OpenSpec in a sheet of our own, the way the backlog's
  offer names them. The backlog's list is *this* project's format and
  `BacklogSetup` is its only implementation; OpenSpec's list is two dozen names
  that change upstream.
- Changing what `Make a Backlog…` does, or the sheet in front of it.
- Offering either record from a board that already has the other.

## Decisions

**`openspec init` runs in a terminal pane, not in the background.** It asks
questions, and the answers write slash commands and skills into somebody's
repository. Running it with `--tools none` to make it quiet would produce an
`openspec/` nobody's assistant can drive; running it with `--tools all` would
write two dozen tools' worth of files into a repository that asked for one.
Ruled out: both. The pane opens a terminal in the project and types
`openspec init`, which is the same gesture as `startBacklogItem` starting an
agent in a pane rather than in the dark, and for the same reason — the thing
that must stay possible is watching it and taking over.

**The backlog's button keeps its sheet; OpenSpec's does not get one.** They are
not symmetrical and pretending they are would cost the honest half: the backlog
sheet exists to *name* the assistants that `abydos-backlog init` would point at
a folder this app owns. OpenSpec's question is asked by `openspec init` itself,
in the terminal, better than a sheet could ask it.

**The absent view is restyled to `FileNoticeView`'s shape rather than the notice
being generalised into a component.** A shared "empty state" type would have to
carry an icon that is sometimes a file's and sometimes a symbol, a title that is
sometimes a filename, a detail line, a path row, a preview button that only a
model has — and the two views have four lines of layout each. What is worth
sharing is the button, which has a drawn appearance, a hover state and a symbol,
and is the part that would visibly drift. So `NoticeButton` moves to a file of
its own and both views use it; the layouts stay separate.

**The offer says which of the two the project has, when it has one.** Ruled out:
showing the empty state whenever either is missing. A project keeping a backlog
is not missing anything, and a pane that says "you could also have OpenSpec"
over a board with work on it is an advertisement. The empty state appears when
there is nothing at all, which is exactly when it appears today.

**A missing `openspec` disables the button and says the install hint in the
view.** Ruled out: offering it anyway and reporting the failure afterwards.
`openspec-board` already requires that the CLI's absence "SHALL be said rather
than being a verb that does nothing", and a button that opens a terminal to run
a command that is not there would be that verb with extra steps.

**The icon is a symbol, not a file icon.** `FileNoticeView` shows the file's own
icon because the subject is a file. The subject here is a project with no record
of work, so the icon is the pane's own — the same one the rail button carries,
so that the view is recognisably the backlog's.

## Risks / Trade-offs

- **A terminal pane opening under somebody who wanted a folder written** →
  That is what `openspec init` is; the alternative is answering its questions
  for them. The button says `…` for the same reason the backlog's does.
- **`NoticeButton` moving out of `FileNoticeView.swift`** touches a file this
  change otherwise has no business in. → It is a move, not a rewrite, and the
  suite plus `make warnings` cover it. The alternative is a second button class
  that looks the same this week.
- **The two offers read as equal choices when they are not** — most projects
  want one. → The view says what each is in a line, which is what the paragraph
  does today for the backlog; it does not recommend.
- **`openspec init` may exit non-zero, or be answered `n`,** leaving no
  `openspec/`. → Nothing is claimed until the directory exists: the pane already
  re-reads on a watcher and on Refresh, and the empty state is what stays until
  there is something to show.

## Open Questions

- **Should a project with a backlog and no `openspec/` be offered one, and
  where?** Not in the empty state, which it never sees. A menu item, or the
  source switch showing a disabled second segment, are both plausible and
  neither is asked for. Left out.
- **Should the empty state also appear when the pane is opened on a project
  whose only record is one this app cannot read** — an `openspec/` in a schema
  `OpenSpecChange` does not understand? Today that project has a board with
  cards in the writing column, which is arguably better than an offer. Left as
  it is.
- **Does `openspec init` want a `--profile`?** The CLI takes one, this project
  has never passed it, and nothing in the report asks for it.
