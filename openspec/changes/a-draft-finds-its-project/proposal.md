## Why

A commit draft takes a while, which is fine — and the answer has nowhere to
land but the pane that asked for it. `ChangesPane.draftMessage()` writes the
result into its own `subjectField` and `bodyView` behind a `guard let self`,
so switching project while the draft is out loses it in one of two ways: the
commit page tab is closed by the switch and the pane is released, so the
draft is dropped without a word; or the sidebar pane, which is rebuilt only
after the new project's branch read, is still on screen for the *new* project
when the draft arrives, takes it, and the next session save writes the old
project's draft into the new project's file. Either way whoever asked has to
stay on the page until it comes back.

And a draft that arrives onto a message somebody has started typing is thrown
away. The completion's own comment says "the draft goes where the field is
empty and is offered where it is not" — and nothing implements the offer. The
two guards are independent besides, so a typed subject over an empty body
takes the draft's description and drops its summary, a message nobody wrote.

Reported on 2026-09-04: "as soon as the project is switched to continue the
work on something else in the mean time, the commit comment is not written
back to the right project. The user is forced to stay on that page. Also when
there is already a commit comment there, the draft result is just thrown
away. Would be better to have the option to use this then. E.g. draft button
gets red and shows 'use draft instead'."

There is no originating `.abydos/backlog` item. `commit-message-drafts` says a
draft "SHALL fill both fields with what comes back" and has no requirement
about a late answer, a switch, an existing message, or the button's states.

## What Changes

- **A draft belongs to the project it was asked for.** The answer goes into a
  root-keyed inbox in AbydosKit, not into a view. The pane applies it only when
  its own root matches; a pane that has gone, or one now showing another
  project, leaves it in the inbox. Coming back to the project — the sidebar's
  changes tool or the commit page — picks it up where a remembered message is
  already restored. Nothing is ever written into another project's session.
- **A draft onto a non-empty message is offered, not dropped.** Both fields
  empty: filled, as today. Either field with text in it: the whole draft is
  held, the button turns red and reads *Use draft instead*, and pressing it
  replaces both fields, as choosing a history entry does. Typing on does not
  disturb the offer; committing, or asking for a new draft, clears it.
- **The button has states, and says them.** *Draft* idle; *Drafting* with the
  spinner `DrawnButton` already has for Push and this button never used;
  *Use draft instead* in red while an answer is held. The commit button's
  refresh stops reading the label to know which state it is in.
- **Nothing is cancelled and nothing is blocked.** The `claude` process runs
  to its end as before; Commit stays enabled throughout, as the spec already
  requires.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `commit-message-drafts`: "A commit message can be drafted from what is
  staged" is amended — the fields are filled when they are empty, and the
  draft is offered when they are not — and three requirements are added: a
  draft finds its project after a switch, a held draft is offered on the
  button, and the button's three states.

## Impact

- **AbydosKit**: `DraftInbox` — drafts keyed by repository root, in memory,
  with `hold`, `take` and `peek`; tests without a window. `ClaudeDraft` is
  unchanged.
- **AbydosApp**: `ChangesPane.draftMessage()` hands its answer to the inbox
  through a closure the sidebar sets, and applies from the inbox on
  construction and on `restore(message:)`; a `draftState` enum replaces the
  label comparison in `updateCommitButton()`; `DrawnButton` gains a tint so
  a button can be red without a new prominence. `SidebarController` drains
  the inbox at its two `restore(message:)` sites and checks a reused commit
  page's root.
- **Driver**: a `draft` step on the commit page against a fake `claude` on the
  run's own `PATH`, and `--switch-project` in the same run, so the report can
  say which project the draft landed in.
- **Cost**: one dictionary entry per project with a draft out; nothing per
  keystroke.
