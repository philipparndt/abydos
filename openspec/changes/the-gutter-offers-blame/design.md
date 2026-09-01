## Context

`CodeView.menu(for:)` builds one menu for the whole view, guarded only on having a document — so the gutter serves the text area's menu. The view already knows exactly where the gutter is (`gutterZone(at:scrollX:)` hit-tests run/number/fold columns for clicks), blame state lives on the view (`isBlameVisible`), and the toggle with its git read lives up the chain (`EditorViewController.toggleBlame` behind `MainWindowController.toggleBlame(_:)`, which the View menu and ⌥⌘B already call).

## Goals / Non-Goals

**Goals:**

- A right-click on the gutter gets a gutter menu; its blame entry shows the
  state in its title and toggles the one blame mode every other handle
  toggles.
- The text area's menu is byte-for-byte what it was.

**Non-Goals:**

- No blame behaviour changes: same column, same `GitBlame` read, same
  per-tab scope.
- No further gutter verbs invented here — breakpoints and folds have click
  gestures with their own specs; the menu can grow entries the day one is
  asked for, and starts honest with one.
- No menu on the blame column itself beyond the same menu: the column is
  part of the gutter.

## Decisions

### One menu decision, made where the click lands

`menu(for:)` converts the event point and, when it falls left of
`gutterWidth` (scroll-adjusted, as every gutter hit-test is), returns the
gutter menu instead of the text menu. Ruled out: a separate right-mouse
handler — `menu(for:)` is where AppKit asks, and the view already answers it.

### The blame item is a title, not a checkmark

"Show Blame" / "Hide Blame", because the menu is transient and the state
lives visibly in the editor (the column is there or it is not); a checkmark
beside a verb reads as two claims. The action is
`#selector(MainWindowController.toggleBlame(_:))` with a nil target, so the
responder chain lands on the same implementation the View menu uses — one
state, three handles, none of them drifting.

### Blame gets written down while we are here

No spec records blame today. The added requirement states the mode minimally
— a column beside the lines naming who last changed each and when it loads —
so the menu entry has something specified to toggle.

## Risks / Trade-offs

- [The gutter menu shadows a future text-menu item somebody expects at the
  far left] → the boundary is the same `gutterWidth` every click already
  respects; nobody aims for Cut in the line numbers.
- [A file outside git] → the toggle already answers that case (an empty
  blame says so); the menu item stays, because offering and explaining beats
  vanishing — the drafting lesson.

## Open Questions

- None held open; the entry grows siblings when they are asked for.
