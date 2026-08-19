## Why

A project with neither record gets a pane that knows about one of them.
Photographed:

    abydos has no backlog

    A backlog is a folder of markdown beside the project: open, ready,
    in-progress, waiting and completed […] Making one writes .abydos/backlog
    and points the assistants installed on this machine at it.

    [ Make a Backlog… ]

    or, in a terminal:  abydos-backlog init

**The pane reads two records and its empty state offers one.** The switch
between the backlog and `openspec/` is the whole shape of this pane now, and the
one door it opens for a project with nothing is `.abydos/backlog`. The other one
— the record this repository itself has been keeping its changes in all week —
is reachable only by knowing to run `openspec init` in a terminal first, at
which point the pane has already told you what it thinks your options are and
they did not include it.

That is also written down as true on purpose. `openspec-board` says, of a
project with neither, "the existing offer to make a backlog is what is shown" —
which was the honest thing to say while the source switch was new, and is the
sentence this change makes untrue.

**And it does not look like the app's other answer to the same question.** The
editor's `FileNoticeView` — a file it cannot show as text — centres an icon, a
title and a one-line reason above a row of flat themed buttons, and the second
screenshot is exactly that: `styles.mov`, "This looks like a binary file.",
`# Open in Hex Editor` and `↗ Open Externally`. The backlog's empty state is a
left-aligned paragraph with a stock `NSButton` in it. Two views that say "there
is nothing here, and here is what to do about it" should not be two designs.

Reported with those two screenshots. **No `.abydos/backlog` item was filed for
it** — the report is the images and this proposal, and saying so is better than
citing a number that does not exist.

## What Changes

- **The empty state offers both records.** Two buttons: making a backlog, which
  is what the one button does today, and setting up OpenSpec.
- **It is drawn like `FileNoticeView`**: an icon, a title, one line of reason,
  and a row of flat themed buttons under it. The button itself is shared rather
  than copied — `NoticeButton` is `private` in `FileNoticeView.swift` today, and
  two of them would be two appearances a week later.
- **OpenSpec is set up by running `openspec init` in a terminal in the project**,
  not silently. `openspec init` asks which assistants to write slash commands
  and skills for, and a pane that answered those questions on somebody's behalf
  would be choosing what gets written into their repository.
- **A machine with no `openspec` says so** rather than offering a button that
  cannot work: the CLI is found through the same login-shell search everything
  else uses, and its absence is already something this pane knows how to say.
- **The terminal lines stay**, one per offer: `abydos-backlog init` and
  `openspec init` are what these buttons are, and somebody who would rather type
  it should be able to read it.
- **Not proposed: writing OpenSpec's scaffolding ourselves.** `BacklogSetup.run`
  exists because the backlog is this project's own format; `openspec/` is not,
  and a second implementation of `openspec init` would be a second answer to
  what an OpenSpec project is — the one that drifts.
- **Not proposed: offering OpenSpec from a board that already has a backlog.**
  The report is about the empty state, and a project already keeping one record
  is not being stopped from anything. Named in the design as the open question
  it is.

## Capabilities

### New Capabilities
<!-- None. -->

### Modified Capabilities

- `backlog`: "A project with no backlog is offered one" becomes an offer of
  both, and says what each button does and what happens when the tool behind one
  is not installed.
- `openspec-board`: the scenario for a project with neither says the backlog
  offer is what is shown. It becomes both offers.

## Impact

- `Sources/AbydosApp/Panel/BacklogPane.swift` — `BacklogAbsentView`, which is
  the whole of the empty state, and the pane that owns its callbacks.
- `Sources/AbydosApp/Editor/FileNoticeView.swift` — `NoticeButton` moves out of
  it so that both views draw the same button. Nothing about the notice itself
  changes.
- `Sources/AbydosKit/OpenSpec/OpenSpecChange.swift` — `OpenSpec` already locates
  the CLI and carries the install hint; it gains the `init` command line beside
  the archive and apply ones it already spells.
- `.abydos/backlog/spec/backlog.md`, which describes the pane today.
- No new dependency, and nothing on a drawing path.
