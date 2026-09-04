## Context

`ChangesPane` is both the view and the model of the commit page: `root` is a
`let` on the view, and both instances of it — the sidebar's changes tool and
the commit page tab — are thrown away and rebuilt by `SidebarController`. A
project switch snapshots the outgoing project's message
(`session.composedMessage = sidebar.composedMessage`,
`MainWindowController+Terminal.swift:393`) before a draft in flight can be in
it, closes every tab (`:431`), and rebuilds the sidebar tool only when the new
project's branch read finishes (`MainWindowController+Loading.swift:107-111`).
In between, the window for project B shows project A's pane. A draft arriving
then writes A's words into the pane on screen for B, and `composedMessage` —
which reads whatever pane is up — carries them into B's session at the next
save (`:483`).

`draftMessage()` (`ChangesPane.swift:1761`) holds the answer's only route: a
detached `Task` with `[weak self]`, `guard let self else { return }`, and two
independent `isEmpty` guards on the fields. The comment above them promises an
offer that was never written.

`DrawnButton` has `isWorking` (`DrawnButton.swift:73`) — the spinner Push
uses — and a `Prominence` that decides its colours (`:219-235`); it has no
tint. `updateCommitButton()` decides whether it is looking at the draft
button by its label (`draft.title == "Draft"`, `ChangesPane.swift:1202`).

The window already keeps per-project state that survives a switch, keyed by
root: `ProjectSessions` (`MainWindowController.swift:45`), and the two places
a remembered message is put back into a fresh pane
(`SidebarController.swift:866` and `:1190`).

## Goals / Non-Goals

**Goals:**

- A draft asked for in project A reaches project A's message and nothing
  else, whether or not the window stayed there.
- A draft arriving onto a message with text in it is offered on the button and
  taken with one press, whole.
- The button says which of its three states it is in.
- The inbox is in AbydosKit and tested; the gesture is driven end to end with
  a switch in the middle.

**Non-Goals:**

- Cancelling a draft. The process cannot be stopped mid-answer today and
  nobody asked; an answer that arrives late is kept, which is strictly better
  than dropping it.
- Writing a held draft to disk. See below.
- More than one draft per project. A new request replaces what is held.
- Merging a draft into typed text. Whole or nothing; the person chooses.

## Decisions

### A `DraftInbox` keyed by root, in AbydosKit, distinct from the message

One value, `[root path: ClaudeDraft.Draft]`, with `hold(_:for:)`,
`peek(for:)`, `take(for:)` and `discard(for:)`, owned by the window beside
`ProjectSessions`. The pane is given two closures by the sidebar: one to hand
a finished draft in, one to ask for a held one.

*Ruled out:* writing the draft straight into `ProjectSession.ComposedMessage`.
That is the message somebody typed, saved to disk and restored as theirs; a
draft written there would become the remembered message of a project whose
field was not empty, which is the second report's fault moved to a different
place. An offer is not a message until it is taken.

*Ruled out:* a strong reference to the pane in the task. It keeps a released
view alive to write into fields nobody will see, and does nothing about the
pane on screen for the wrong project.

### The pane applies only what is its own

On arrival, the pane applies the draft only if `draft.root == self.root` and
it is in a window; otherwise the draft stays in the inbox. On construction
and in `restore(message:)`, the pane asks the inbox for its root. A held draft
found then goes through the same rule as a fresh one: empty fields are
filled, non-empty fields make an offer.

*Ruled out:* checking the window's current project instead of the pane's
root. The window's project is already B while A's pane is on screen, which is
the gap the fault lives in; the pane's own root is the only thing that is
true throughout.

`showCommitPage` reuses a page by identifier without asking its root
(`SidebarController.swift:1139`); the same guard goes there, so a commit page
left from project A is not handed project B's draft.

### A non-empty message makes an offer; the button carries it

Either field with text: the whole draft is held and `draftState` becomes
`.offering`. The button reads *Use draft instead*, tinted red, and pressing it
calls the existing `fill(subject:body:)` — the replace-both semantics
`commit-message-history` already established for choosing — then returns to
`.idle`. Typing leaves the offer standing. Commit clears it, since the message
it was offered against is gone; a new *Draft* is not possible while offering,
because the button is the offer — pressing it takes the draft, and the next
press drafts again.

*Ruled out:* filling whichever field is empty and offering the rest. It is
what the code half-does now and it makes messages nobody wrote.

*Ruled out:* a second button, *Draft* beside *Use draft*. Two controls for one
decision, in a row that is already full at the compact width.

*Ruled out:* a sheet or toast asking. A toast passes; the offer has to stand
until it is taken or the message is committed.

### Three states, as an enum, not a label

`private var draftState: DraftState` — `.idle`, `.drafting`, `.offering` —
drives label, `isEnabled`, `isWorking` and tint from one switch, and
`updateCommitButton()` asks the state rather than comparing the title.

*Ruled out:* keeping the label comparison and adding a second one. A button
relabelled *Use draft instead* already falls out of the `"Draft"` branch and
stops having its availability and tooltip refreshed; a third label makes
three ways to be wrong.

### Red is a tint on `DrawnButton`, not a prominence

`var tint: NSColor?` consulted by `fillColour`/`textColour`, nil for every
button today. The colour is the palette's `gitConflict`, which every scheme
already defines as its red; no new theme key.

*Ruled out:* a fourth `Prominence`. Prominence says how loud a button is;
this is what colour it is, and an offering button is still quiet.

### In memory only

The inbox is not written to disk. A draft describes the staged diff at the
moment it was asked for; after the app is quit and reopened the diff may be
anything, and a stale draft restored as an offer would describe a commit that
no longer exists. A project the window never returns to keeps its draft until
the app quits, and loses it then, which is the honest lifetime of an answer
about a moment.

*Open:* whether the inbox should drop a draft when the repository's staged
set changes underneath it, for the same reason. It is cheap — the changes
pane already reads the status — and it is not decided here because it wants a
look at how often a draft's diff still matches when somebody comes back.

## Risks / Trade-offs

- [The draft arrives while A's pane is on screen for B] → the pane's root is
  A, the window's is B, the pane declines and the inbox holds it; A's next
  pane takes it. The exact case in the report, and the test.
- [The fields were filled by a restored session after the draft was held] →
  the held draft meets a non-empty message and becomes an offer rather than a
  fill; nothing typed or restored is overwritten unasked.
- [Two drafts requested for one project from two windows] → the later
  replaces the earlier in the inbox; a draft is not precious and the process
  still runs to its end.
- [`isWorking` reserves room for the spinner] → the button is a few points
  wider at rest, as Push is; measured in the driven run's report of the row.
- [Commit pressed while offering] → Commit stays enabled, as the spec
  requires; the offer is cleared with the message it was offered against.
