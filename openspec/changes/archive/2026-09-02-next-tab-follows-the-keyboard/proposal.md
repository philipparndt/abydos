## Why

The panel's tab strip has no keyboard route. ⌘⇧] and ⌘⇧[ — the View menu's
*Next Tab* and *Previous Tab* — switch editor tabs wherever the keyboard is, so
pressed in a terminal they change the file behind the panel and the panel does
not move. tmux's own windows can be walked with tmux's prefix keys, because
that is tmux and the strip follows it; the panel's own tabs — the `tmux` tab and
the `Local` terminals beside it — can be reached only with the mouse or through
the overflow menu. The `tab-overflow` spec says so in its own words: "for the
panel's strip there is not even a keyboard route, since ⌘] and ⌘[ move between
editor tabs."

So somebody in a tmux tab is boxed in twice: tmux's keys move only among tmux
windows, the app's keys move only among editor tabs, and nothing reaches the
`Local` tab next door — or comes back from it.

There is no originating `.abydos/backlog` item: this comes from a direct
report, 2026-09-02 — "it is possible to navigate through tmux panes, but not
through terminal window tabs … it is not possible to navigate from another tab
to tmux and the opposite way".

## What Changes

- **Next Tab and Previous Tab follow the keyboard.** With the keyboard in the
  panel they select the neighbouring tab on the strip of the column being typed
  in, wrapping at either end, and take the keyboard there as a click would. In
  the editor they do what they do today.
- **What "the strip" is follows what is shown.** When tmux's windows have a
  strip of their own along the bottom, the top strip's neighbours are the
  panel's tabs — `tmux`, `Local`, a debugger — and tmux's windows keep tmux's
  keys. When tmux's windows share the one strip, cycling steps through them too,
  because they are the tabs on it.
- No new shortcut. The two keys people already reach for start meaning what the
  strip under the cursor shows.

## Capabilities

### Modified Capabilities

- `terminal`: gains a requirement that Next Tab and Previous Tab act on the
  panel's strip while the keyboard is in the panel.
- `tab-overflow`: its first requirement's account of the strip having no
  keyboard route is amended, since there now is one.

## Impact

- **AbydosApp**: `MainWindowController.selectNextTab` and `selectPreviousTab`
  ask `isTerminalFocused` first; `BottomPanel` gains `selectNeighbouringTab`;
  `PanelTabStrip` gains `selectNeighbour`, which drives the same `onSelect` a
  click does, so every kind of tab — a terminal, a tmux window, a debugger —
  is selected the way it already is.
- **Driver**: `--next-tab-in-panel` presses the keys with the keyboard in the
  panel and then in the editor and says what each did, so the claim can be
  checked without a screenshot. `LaunchOptions.swift` and `AppDelegate.swift`
  are on the length list and grow by a few lines for it.
- **Cost**: none.
