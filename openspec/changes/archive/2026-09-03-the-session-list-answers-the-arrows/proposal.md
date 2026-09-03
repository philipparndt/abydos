## Why

The running-sessions popup opens with the keyboard in its filter field, and
there is no way out of the field but the mouse. ⏎ chooses the first row still
shown, which is the right answer when a filter has narrowed the list to one and
no answer at all when it has narrowed it to five. Asked for on 2026-09-03: "it
should be possible to navigate out of the search field using cursor down."

This was named a non-goal when the list was built — *"keyboard navigation of the
rows beyond ⏎ on the filter. Arrow keys in a drawn list are a change of their
own"* — because the rows are drawn rather than a table, and a drawn list has no
selection until somebody gives it one. This is that change.

## What Changes

- **↓ in the filter moves into the rows**, selecting the first one shown. The
  field keeps everything else it does, including the text somebody has typed.
- **The rows answer the arrows.** ↓ and ↑ move the selection between the
  sessions, skipping the group headers and the footer, and the selection is
  scrolled into view. ⏎ opens the selected session, which is what clicking its
  row does.
- **↑ from the first row goes back to the field**, with the caret at the end of
  what was typed, so narrowing and choosing are one movement in each direction.
- **Escape puts the list away**, as it already does from the field.
- **A selected row is drawn as selected**, in the palette's selection colour
  rather than the hover tint, so which row ⏎ will open is never a guess.
- A row selected by the keyboard and a row under the pointer are drawn
  differently, because they are two different questions.

## Capabilities

### Modified Capabilities

- `running-sessions`: the popover's requirement gains what the arrows do, what
  ⏎ does with a selection, and that a selected row is drawn as selected.

## Impact

- **AbydosApp**: `RunningSessionsListView` gains a selection, `keyDown`, and the
  drawing for it; `RunningSessionsController` answers `moveDown:` from the field
  and hands the keyboard over. The popover's driven report gains the selection so
  a run can say where the keyboard went.
- **Cost**: none.
