## Why

Two reports about the list ⇧⌘A opens, from the first afternoon of using it:

- "the selection jumps while usage, most likely due to background updates on
  the items"
- "when open the dialog again, the selection remains the same, which is nice
  but the focus is on the search. This is confusing"

**The first answer was half of one, and the report came back: "the selection is
still jumping around."** A lit row was remembered as a *number*, and the list is
rebuilt on every hook event and once a second by the staleness clock — so the
selection and the hover moved to whatever now sat at those numbers, under a
motionless pointer and with nobody touching a key. Fixing that made the
highlight stay on its own session, and the highlight still moved: because the
*rows* move. The order is a good one — where a session is, never when it spoke —
but it is computed afresh from data that keeps arriving. A session learns its
tmux window and leaves the windowless tail; a session in another project appears
and its group takes its place by name; the mirror seeds a badged window and drops
it again a second later. Every one of those is a row changing places, and the
selection rides along with its session, which from the outside is a selection
that jumps.

So the order is now decided when the list opens and held while it is open.

And the second: reopening restores the row, correctly, while the caret starts in
the filter. A filled row and a live caret both claim the next keystroke, and ⏎
then acted on the first row rather than the lit one — so the highlight was not
merely confusing, it was wrong about what would happen.

## What Changes

- **The order is held while the list is open.** Decided on the first reload
  after it opens; anything arriving afterwards goes at the end, where it can be
  seen to have arrived. Reopening decides it again — that is the one moment a
  fresh order costs nobody anything.
- **Both highlights are re-found on every rebuild.** The selection by the
  session's own id, and dropped rather than left pointing at a stranger when
  its row is gone. The hover from where the pointer *is*, asked of the window,
  since nothing tells a view that the thing under a still pointer has changed.
  Both are still needed with the order held: a session that ends still takes
  its row away.
- **A remembered selection is drawn as a ring**, not a fill, while the filter
  has the keyboard, and fills in when the rows take it. Two fills a shade apart
  cannot be told from the hover tint, and the pointer resting on one row while
  another is remembered is the ordinary case.
- **⏎ in the filter acts on the lit row**, and on the first one when none is
  lit. The highlight is a promise about what ⏎ does.
- **The filter takes the keyboard on every opening**, with what was typed last
  time selected so the next letter replaces it. The palette keeps its window
  and controller between openings, so nothing about its appearing did that for
  the second one.

## Capabilities

### Modified Capabilities

- `running-sessions`: says that the two highlights survive a rebuild, what a
  remembered selection looks like and what ⏎ does with it.

## Impact

- **AbydosApp**: `RunningSessionsListView` holds the order it came up in and
  re-finds both highlights;
  one more state in the row's drawing; `RunningSessionsController` gains
  `focusFilter()`; the palette calls it on every opening.
- **Driver**: a `wait` key in the list's key instrument, so a rebuild actually
  happens between two reports.
