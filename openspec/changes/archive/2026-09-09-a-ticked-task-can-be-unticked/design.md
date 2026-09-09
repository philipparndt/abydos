## Context

A card in the In progress column shows a tip listing its open tasks when the
pointer rests on it; a click on a row ticks that line of `tasks.md`. The write
is `BacklogItem.tick(line:in:)`, which goes through `ticking(line:in:)`: the line
has to still read as the unticked step it was when the tip was read, everything
else is kept byte for byte, and a line that has moved on is refused and the tip
re-read. After a tick the tip calls `show()`, re-reads the file, and the ticked
row is gone — the tip lists what is open. Neither the tip nor the board pane
owns an `NSUndoManager`, so ⌘Z finds nobody.

## Decisions

**The untick is the tick's mirror, and nothing more.** `unticking(line:in:)`
requires the line to read as a *ticked* step whose text is the one that was
ticked, replaces the first `[x]` with `[ ]`, and keeps every other byte. A line
that no longer says that — an agent rewrote the file, the task was moved — is
refused, nothing is written, and the tip is re-read. The refusal is the whole
safety of offering it: an undo that guessed at a line would be worse than none.

**Two ways in, one write.** The row somebody just ticked stays in the tip,
ticked and dimmed, with *Undo* at its end, until the tip is next re-read or the
pointer leaves; clicking the row unticks it. And the board pane owns an undo
manager, registers each tick's reversal with the action name *Tick*, and
answers ⌘Z and the Edit menu's *Undo Tick* while it or the tip has the
keyboard. Both call the same `untick(line:text:in:)`.

*Ruled out: undo through the file's own history.* Reverting `tasks.md` from
git would take every other edit with it, and a tick is one character.

*Ruled out: a confirmation before the tick.* A dialog on every tick is what the
one-click tip was built to avoid; an undo after is the same safety at no cost
to the ordinary case.

**Only this window's ticks, and only the last one per file.** The undo stack is
the pane's: a tick an agent wrote is not this window's to undo, and the pane
forgets its registrations when the project changes. Redo is the tick again,
through the same check.

**Reported by the driver.** The tip's driving verb gains an `undo` step that
reports what the file says afterwards, so the round trip — tick, undo, the
line reads `[ ]` again with the same text — is a line a run prints.

## Risks / Trade-offs

**The dimmed row could be mistaken for an open task** → it is drawn ticked, in
the dim colour, with the word *Undo* where the others have none, and it goes
with the next re-read.

**⌘Z while the editor has the keyboard** → goes to the editor, as it should;
the pane answers only while the board or the tip is first responder.

## What the run showed, 2026-09-09

On a scratch copy of this repository's own board, `--backlog-tick
a-java-edit-reaches-the-running-jvm:1` ticked the first open task — 5.2 — and
the card read 25 of 31; `--backlog-untick` on the same card took it back, and
the file's line 92 read `- [ ] 5.2 **Measure the build before settling this.**`
with the words unchanged. The tip kept the ticked row with *Undo* between the
two, which is the row the untick went through.

## Release note

> **A tick on a card can be undone.** The task you just ticked stays in the
> card's list for a moment, dimmed, with *Undo* at its end; ⌘Z takes it back
> too while the board has the keyboard. The undo is as careful as the tick: it
> writes only if the line still reads as the task that was ticked, and says so
> when the file has moved on.

## Open Questions

None.
