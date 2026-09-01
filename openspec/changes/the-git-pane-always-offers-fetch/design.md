## Context

The repository row has two controls: the traffic verb, chosen from the state and
fired by ⌘⏎, and a glyph beside it. The glyph's behaviour is already right —
it fetches where there is a remote — and its problem is that it is a picture.
The row's own comment explains why the controls are on the row at all: this pane
has no header to put a button in.

## Goals / Non-Goals

**Goals:**

- Fetching reachable in one press from the git pane in every repository state.
- The control says what it does, in the word people are looking for.

**Non-Goals:**

- Changing what the traffic verb is, or what ⌘⏎ fires.
- Adding a header to the pane to hold buttons. That was ruled out when the row
  gained its verbs and nothing about this reopens it.
- Fetch on a timer, or on window activation. A fetch is a network call somebody
  asks for.

## Decisions

**A word, not a glyph.** The control is titled `Fetch`.

*Ruled out: keeping the glyph and improving the tooltip.* The report is that the
button was not found; a better tooltip is only readable by somebody who already
hovered over it, which is the group that does not need it.

**Nothing where there is no remote.** The glyph used to fall back to a local
re-read there. The pane already re-reads on every filesystem event, the fallback
was doing work the watcher had done, and a control that quietly means two
different things depending on state is what made the glyph unreadable in the
first place. Re-reading stays on the row's context menu.

*Ruled out: showing `Fetch` disabled with a reason.* That is the right answer
when a verb is temporarily unavailable — it is what the `Draft` button now does.
It is the wrong answer for a repository that has no remote and never will: a
permanently grey button is furniture.

**Two `Fetch`es when the repository is level, and that is allowed.** The row's
verb reads `Fetch` when level, and the new control says `Fetch` beside it. It
looks like a duplicate and is one, for one state out of four.

*Ruled out: dropping `Fetch` from the state verb and leaving it blank when
level.* A row whose verb disappears is the fault being fixed, one control over.

*Ruled out: hiding the new control when the state verb happens to be `Fetch`.*
Then the button is missing again, in the one state where it is least expected to
be, and "always there" was the request.

## What implementing it found

**The local re-read was already on the menu.** `Read the Repository Again` has
been on the repository row's context menu since the glyph was added, with a
comment saying why — after a rebase in a terminal there is nothing to fetch and
no reason to wait for one. So removing the glyph's no-remote fallback moves
nothing and loses nothing; the migration line in the spec was already true when
it was written.

**The row's second verb was glyph-only on purpose, and that had to be undone.**
`ActionableRowView`'s own comment made the case: the width arithmetic exists so
a row is never truncated to make space for a button, and two sets of spellings
competing for one trailing edge is that problem twice — a symbol at a fixed
twenty points kept it to one subtraction. What that bought was a verb nobody
could read, which is the report.

So the second verb may now carry words, and the row keeps the rule rather than
abandoning it: the second verb is measured like the first, and where there is
not room for both, **the second one is what goes**. The row's own name still
comes first. That is the risk below, answered in the arithmetic instead of in a
promise.

## Risks / Trade-offs

**A titled control is wider than a glyph, and the row is narrow.** → The row
already truncates its own text and has a rule for it; `Fetch` is five
characters. If the row cannot hold it at a large zoom in a narrow pane, the
control is the last thing to be dropped and the row says so, rather than
overlapping.

**Somebody used the glyph for its local re-read.** → It has existed since
0.10.0, it re-read only what the watcher already re-reads, and the verb stays on
the context menu. Worth saying in the release notes rather than treating as
silent.
