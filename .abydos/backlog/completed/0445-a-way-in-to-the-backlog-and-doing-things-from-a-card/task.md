# 445. A way in to the backlog, and doing things from a card

Three things reported from using the board, and they are one piece of work
because they are all the same gap: the backlog is a thing you can *look* at and
almost nothing you can *do* from.

## 1. There is no way in except a keyboard shortcut

⇧⌘B opens it, and Agent ▸ Backlog is the only other route. Every other pane in
this window has a button on the left rail — that is where somebody looks for
"show me the X" — and the backlog has none, so the feature is invisible to
anybody who has not been told the shortcut.

**Bottom left of the toolbar, and the first item there.** That is what was
asked for, and the rail already holds the panes that answer "what is going on
with this project".

## 2. A card knows its worktree and will not take you there

`abydos-backlog start` makes a worktree, `BacklogRun` records it, and the card
already *shows* the branch — `backlog/0435-…` under the title. What it will not
do is open it. So the one thing somebody wants from an item being worked on —
go and look at it — is a copy of a path out of a card and a `cd` in a terminal.

Two readings, and they are different gestures:

- Open the worktree **as a project**, which is what "jump to the working tree"
  most likely means: another window, or this one, on that checkout.
- Open a **terminal** in it, which is where an agent is actually working.

Both are cheap and the item should probably offer both rather than guess — the
project switcher already knows how to open a directory, and the panel already
knows how to start a terminal somewhere.

Note `run.isPresent` already distinguishes a worktree that is still there from
one somebody deleted with `rm -rf`, so the action can be offered only when there
is something to open, rather than failing afterwards.

## 3. A project with no backlog offers nothing

`Backlog(projectRoot:)` on a project without `.abydos/backlog/` gives an empty
board: five empty columns and no way to make it not empty. `abydos-backlog init`
exists and does the whole job — the folders, `project.md`, `config.json`,
`AGENTS.md`, and the assistant files — but only from a terminal, and only if
somebody already knows the command exists.

So: when there is no backlog, the pane says so and offers to make one. And once
there is one, **new items are made from the pane too** — `abydos-backlog new`
from a button, landing in `open/`, with the title asked for and the file opened
so it can be filled in.

The rule the tool is explicit about must survive this: **new items go to `open/`,
never to `ready/`**. `ready` is a promise the deciding is done, and neither the
tool nor an agent may make it. A "New item" button that dropped things into
`ready` would quietly turn the one human gate into a formality.

## Ruled out

**A chooser for the assistants, in the "Make a Backlog" sheet.** `init` on the
command line asks which assistant works this backlog, and the obvious thing was
to ask the same question with checkboxes. Not done: `init` already has a good
answer for when it is not talking to a terminal — the ones that are installed —
and a second copy of that question is a second place for it to drift. The sheet
names them instead, and says that running `init` again adds another. If somebody
wants the question, the answer is the command, which is the point of the command
existing.

**A "New item" button per column.** The natural place for it looked like the
head of each column, which is where every other board puts one. It is exactly
the wrong place here: a button at the head of `ready` would file into `ready`,
and that is the one promise a button may not make. One button, in the header,
that does not ask where.

**Watching for a backlog appearing in a project that has none.** FSEvents wants
a path that exists, and the only path that certainly does is the project root —
watching the whole source tree to notice one folder being made. So a backlog
made in a terminal is not noticed live; Refresh, or showing the pane again,
picks it up, and a backlog made from the button starts the watcher on the spot.
Written down rather than fixed, because the cost is one click and the fix is a
recursive watch of everything.

**Lighting the rail button while the board is showing.** The terminal button
does this — `setPanelVisible` lights it — but the panel's selection is per tab,
so the backlog button would have to follow which tab is in front, and every
other pane in that group (review, debug) would want the same. Left undone rather
than half done: the button opens the backlog and says nothing about whether it
is open.

**What the screenshots showed that nothing else could.** The board and the
absent view were photographed; the menus were not, because a menu is not on
screen until somebody clicks, so they are printed instead — see
`--backlog-menu`, `--backlog-init` and `--backlog-new`, added for this. Two
things came out of looking rather than reasoning: the `checklist` symbol does
render at the strip's size (a missing SF Symbol draws nothing at all and the
button would have looked like a gap), and the card for the item whose worktree
had been deleted drew no branch at all — which is the same `isPresent` rule the
new menu entries use, visible on the card, and is why the two cannot disagree.

Worth reading first rather than rediscovering: `BacklogCommands.swift` already
implements `init` and `new` as commands, and `BacklogSetup.swift` is what `init`
calls. Doing either of these from the pane should call the same code rather than
grow a second implementation — the whole design of this backlog is that the app,
the command line and an agent are reading and moving the same files, and two
implementations of `init` is two answers to what a backlog is.

## Steps

- [x] A button on the left rail, first, that shows the backlog
- [x] A card offers its worktree — as a project, and as a terminal — and only
      when the worktree is still there
- [x] An empty project's board offers to make a backlog, through `BacklogSetup`
      rather than a second implementation
- [x] A button that makes a new item, landing in `open/`, and opens it to fill in
- [x] Check by eye that a new item cannot reach `ready/` from the pane
- [x] Write down here what was ruled out on the way
- [x] `spec/backlog.md` says what the project now does
