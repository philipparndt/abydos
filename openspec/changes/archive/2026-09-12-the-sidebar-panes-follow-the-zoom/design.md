## Context

Two paths carry a zoom to a view. `ScaledControls` (`Controls/ScaledControls.swift`)
holds a weak registry of `ScaleFollowing` members — `DrawnButton`,
`DrawnChoice`, `ScaledLabel`, `ScaledSearchField`, `ScaledHeights`,
`DrawnCheckbox` — and calls `applyTheme()` on each when `.abydosSettingsChanged`
posts. The other path is `MainWindowController.applySettings`, which forwards
to the editor, the navigator, the tool strip and the bottom panel, and the
bottom panel to its panes. The sidebar is on neither: its panes are rebuilt
only in `applyPalette`, and only when `Theme.apply()` says the palette moved.

The five screenshots, read against the code:

| Control | Built | On a zoom |
| --- | --- | --- |
| Backlog *List / Board*, *Backlog / OpenSpec* | `NSSegmentedControl`, `uiFont(11)` | font re-set by `applySettings`; bezel from `controlSize`, so only the glyphs grow; the second switch and *Refresh* are not re-set at all |
| Structure *Filter symbols*, *No file open* | raw `NSSearchField`, raw `NSTextField` | nothing — `applyThemeChange` exists and nothing calls it |
| Scratches *Search scratches*, empty label | raw `NSSearchField`, raw `NSTextField` | nothing; the two buttons beside them are `DrawnButton` and follow |
| Scratches `ABYDOS` header and rows | drawn with `Theme.current.scaled(…)` | right when redrawn, which a zoom does not cause |
| Pull requests *Only me / My teams too*, refresh | `DrawnChoice`, `DrawnButton` | follows, by registration |

## Decisions

### 1. Join the registry; add no forwarding

Each raw field or label becomes the library's measured member for it, and
each segmented control the drawn one, exactly as the pull-request list did in
the change that made the library. The alternative — teaching `SidebarController`
to forward `applySettings` to every pane — is the path that produced these
four: it is a list somebody has to remember to add to, and the Structure
pane's dead `applyThemeChange` is what forgetting looks like.

### 2. `DrawnChoice` where a bezel was the size

`NSSegmentedControl` walls out at `controlSize`'s largest value; `DrawnChoice`
was written for this control in this pane (its doc comment names it). The
Backlog pane's two switches become one each; *Refresh* becomes a
`DrawnButton` held by the pane rather than a local.

### 3. Rows re-measured through `ScaledHeights`

The Structure and Scratches outlines draw their rows from `Theme.current` and
are right on the next draw; what a zoom does not cause is a draw. A
`ScaledHeights` member per pane calls `noteHeightOfRows` and `reloadData` in
its `applyTheme`, which is what the library's other tables do.

## What was measured, 2026-09-12

Window captures on a scratch checkout, each pane at 1.0 and then the same
pane after three *Zoom In* presses while it was on screen — the second is the
claim, since a pane built at a zoom proves only that it read the scale once.
`--sidebar <tool>` for the three sidebar panes and `--backlog board` for the
panel's, with `--tree "zoom-in,zoom-in,zoom-in,settle:1"` for the zoomed
capture; the `zoom-in` and `zoom-out` tree steps are new, because
`command:Zoom In` wants the key window and a run launched from a terminal
never gets it.

| Pane | At 1.0 | After three zoom-ins, pane already up |
| --- | --- | --- |
| Structure | *Filter symbols* and *No file open* at the sidebar's size | both at the new size, the label centred under the field as before |
| Scratches | field, buttons, `GLOBAL` / `ABYDOS` headers, rows | all at the new size; the rows and headers re-measured, not only redrawn |
| Pull requests | the trouble sentence for a repository with no GitHub remote | wrapped at the new size beside the switch that already followed |
| Backlog | *List / Board*, the five counts, *New item…*, *Start the next ready item*, *Refresh* | all at the new size, and the switch's shape grew with its words rather than its glyphs alone |

**Seen on the way, not this change's.** At three steps up the sidebar is
narrower than *New Scratch* and *New Global* side by side, and the second is
clipped at the pane's edge; the buttons were the library's before this change
and this is their width, not their size. And `--sidebar` at one second can
lose to `--panel-maximize 1` at the same second — the tool then opens as a
popover over a still-maximised panel and the capture shows the tree. The runs
here toggle the panel at 0.3 s; a driver that ordered the two would be a small
change of its own.

**Widened by one line.** *New item…* and *Start the next ready item* became
`DrawnButton`s alongside *Refresh*: one drawn button beside two bezelled ones
in the same header is three sizes, and the task named only the third.

## Release note

> **Four panes now follow the zoom.** The Backlog pane's switches, the
> Structure pane's filter and its empty label, and the Scratches pane's search
> field grow and shrink with everything else, as the pull-request list's
> controls already did.

## Open Questions

None.
