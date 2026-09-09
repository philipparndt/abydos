## Why

The maintainer, 2026-09-09: *"when checking tasks in the backlog there shall be
an undo."* A card in the In progress column lists its open tasks when the
pointer rests on it, and a click ticks one where it is read — 0.19.0's card
tip. A tick is a write to `tasks.md`, one character, made at the moment of the
click, and there is no way back from it but a text editor: the row disappears
from the tip the instant it is ticked, because the tip lists what is *open*, so
there is nothing left on screen to click again, and ⌘Z goes nowhere — neither
the tip nor the board has an undo manager.

A slipped click on a list of thirty ticks the wrong one, and the wrong tick is
the one the house rules argue hardest against: *"Never tick ahead. A `[x]` means
somebody could go and look at it."* An undo is what makes a one-click tick safe
to offer at all.

What already exists and shapes the answer: `BacklogItem.ticking(line:in:)`
checks at the moment of writing that the line still reads as the unticked step
it was, and writes nothing otherwise, because an agent in a worktree may have
rewritten the file since the tip was read. An untick has the same shape in the
other direction — the line has to still read as the ticked step it just became.

There is no originating `.abydos/backlog` item: this comes from a direct
request, 2026-09-09.

## What Changes

- **A tick can be undone, from where it was made.** The row somebody just
  ticked stays in the tip for a moment, ticked and dimmed, with the one word
  *Undo* beside it, and goes with the next re-read or when the pointer leaves.
  Clicking *Undo* unticks the same line.
- **And from the keyboard.** ⌘Z while the tip or the board pane has the
  keyboard unticks the last tick this window made, through an undo manager
  the pane owns, so the Edit menu's *Undo* names it — *Undo Tick* — the way
  every other undoable thing in the app is named there.
- **Written the way the tick was.** `BacklogItem.unticking(line:in:)` is the
  mirror of `ticking`: the line has to still read as a ticked step with the
  same text, everything else is kept byte for byte, and a line that has moved
  on is refused and the list re-read. An undo that guessed would be worse than
  none.
- **Not a general edit.** Only the app's own ticks are undoable, and only in
  the window that made them; a tick an agent wrote in the file is not this
  window's to undo.

## Capabilities

### Modified Capabilities

- `backlog`: what ticking a task from a card offers — the tick, and the way
  back from it.

## Impact

- **AbydosKit**: `BacklogItem.unticking(line:in:)` and `untick(line:in:)`
  beside their counterparts, with the same tests turned around.
- **AbydosApp**: `TaskTip` keeps the ticked row for a beat with *Undo*; the
  backlog pane gets an `NSUndoManager` and registers each tick's reversal.
- **Driver**: the `--tasks-tick` verb gains an `undo` step that reports what
  the file says after.
