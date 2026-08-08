# Filter projects as you type, and dock the terminal in the tool strip

`926d5cdce` · 2026-07-30

The switcher already accepted typing, but invisibly: it jumped to a match with
no indication of what had been typed or why the selection moved. It now has a
visible field that filters the list, matching on name and path so "3d" finds
everything under ~/dev/3d. Arrow keys and Return work from the field, so
filtering and choosing are one gesture, and Escape clears the filter before it
closes the popover.

Ranking lives in IdeaiKit as ProjectFilter rather than in the popover, so the
rules are testable without a window: a name that starts with the query first,
then any name match, then most recently opened.

The terminal also gets a button at the bottom of the left strip, which is where
IDEA puts bottom-docked tool windows and where the panel actually appears. It
lights while the panel is showing.

171 tests.
