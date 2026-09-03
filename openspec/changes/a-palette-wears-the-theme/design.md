## Context

`PalettePanel` is the window both palettes live in: titled, full-size content,
hidden title, transparent title bar. `RunningSessionsPalette` and
`SymbolPalette` each make one, size it over the parent window and order it in.

`Theme.current` is the app's palette. `NSWindow.appearance` is AppKit's, and it
decides what the system draws inside the window: the title bar's material, a
search field's bezel, a scroller. Unset, a window inherits the application's,
which is the system's.

`RunningSessionsPopover` sets `appearance` from `Theme.current.isLight` in its
initialiser. That line is the whole of the fix; the question is where it goes.

## Goals / Non-Goals

**Goals:**

- One window, one appearance, taken from the theme.
- Both palettes, and whatever palette comes next.

**Non-Goals:**

- Drawing the title bar ourselves. The band is the right shape and the right
  material; it was only the wrong palette.
- A theme-change notification. The window is dressed as it is shown, which
  covers a theme changed while it was away without anything having to watch.

## Decisions

**In the window class, on the way to being shown.** Two alternatives were
weighed. In each palette's own `show`, which is where the running-sessions
palette first had it — two copies, and the next palette makes three. Or in the
initialiser, which is once but too early: the window outlives a theme change.
Overriding the two methods that put a window on screen is the one place that is
both shared and current.

*Ruled out: watching for theme changes.* Nothing else about these windows is
live-updated, and a window nobody can see does not need to be right until it is
shown.

## Risks / Trade-offs

**An override on a common method** → `orderFront` and `makeKeyAndOrderFront` are
called by us and by AppKit; setting an appearance is idempotent and costs a
comparison, so being called more often than needed does nothing.

**`Theme.current` read while ordering a window in** → It is the main thread by
definition here, which is what `theme-access` requires.
