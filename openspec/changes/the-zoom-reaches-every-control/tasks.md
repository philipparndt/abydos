## 1. The arithmetic, tested without a window

- [x] 1.1 Add `ControlMetrics` to AbydosKit: the height, the horizontal padding and the corner radius of a drawn control, from a design-time font size and a scale, with the measured line height given in rather than assumed.
- [x] 1.2 Add `CommitRowMetrics` to AbydosKit: a commit row's height from the two measured line heights and the paddings, so the row is derived rather than the constant 40 it was.
- [x] 1.3 Tests beside `PanelRowSnapTests` over all nine zoom steps: a control's height at 2.0 is twice its height at 1.0 within rounding, and a commit row is never shorter than the content it is given.

## 2. The library

- [x] 2.1 Create `Sources/AbydosApp/Controls/` and move `DrawnButton` into it unchanged, keeping its two callers working.
- [x] 2.2 Add `ScaledControls`, the registry: weak boxes, one `.abydosSettingsChanged` observer, a `reapply()` walk that drops empty boxes, and a count the driver can read.
- [x] 2.3 Generalise `DrawnButton` into the library's drawn push button and glyph button, taking their metrics from `ControlMetrics` and registering on init.
- [x] 2.4 Add the drawn checkbox. Compare it against a 1× capture of the system's; if it cannot be made to read as a checkbox, stop, leave `Hide read` and `Whole file` bezelled, and say so here rather than dropping it quietly.
- [x] 2.5 Add the choice control. Try drawn first; if the arrow-key behaviour between segments cannot be kept, keep `NSSegmentedControl` and make it a *measured* member, which the design allows.
- [x] 2.6 Add the measured search field: AppKit's field, given `Theme.uiFont` and a scaled height constraint, both re-taken on a scale change.

## 3. The log page

- [x] 3.1 Move the search field and the scope control onto the library.
- [x] 3.2 Re-take the commit table's and the file table's row heights on a scale change, from `CommitRowMetrics`, and re-lay-out the rows rather than leaving the height read at build time.
- [ ] 3.3 Driven: capture the log page at 1.0 and at 2.0 and show the whole of the short hash inside the row at both, which is the report.

## 4. The commit page

- [x] 4.1 Move `Stage`, `Unstage`, the `…` verb, `Draft`, `Commit`, `Push`, the message-history control and the `Amend` checkbox onto the library.
- [x] 4.2 Move the description chevron onto the library's glyph button.
- [x] 4.3 Read `PanelRowSnap` before writing anything for the detail area, and settle the design's open question: either the existing machinery covers this split or it does not. Recompute the division on a scale change, by whichever answer that is.
- [ ] 4.4 Driven: toggle presentation mode with the commit page open and show the detail area at the working size afterwards.

## 5. The pull-request pages

- [x] 5.1 Move the review page's header — the review and check-out verbs, the two switches, the view-mode control — onto the library.
- [x] 5.2 Move the list's scope control and the glyph beside it onto the library.
- [ ] 5.3 Driven: capture both at two scales.

## 6. The project tree's palette

- [x] 6.1 Re-apply the outline view's background and the container's colour in `ProjectNavigatorViewController.applySettings()`, beside the row height and the indentation that are already re-applied there.
- [x] 6.2 Give the navigator's container the `colourSource` closure its sibling containers in `MainWindowController+Layout` already have.
- [ ] 6.3 Driven: switch the palette with the tree showing and capture it, which is the screenshot that was reported — one pane, half light and half dark.

## 6b. What running it found

- [x] 6b.1 The diff view hears `.abydosSettingsChanged` and *discarded* it: its handler guarded on the two diff preferences only, so a zoom matched neither and returned. It re-takes its font and line height first now, and rebuilds when they move.
- [x] 6b.2 `ControlMetrics.verticalPadding` was 8, which put a one-line control at 23 points at 1× against the bezel's 20 — every converted button came out fatter than the one it replaced, and nearly filled the commit page's 26-point section strip. Five now, with a test asserting the size of the bezel it replaces.
- [x] 6b.3 The commit page's `Stage` / `Unstage` were the height and nothing else: confirmed against the report once the padding was five. The fill was never wrong — a pill four points too tall reads heavier than one that is not, which is worth knowing before chasing a colour that was correct.

- [x] 6b.4 The commit page's `Summary` placeholder did not follow. `NSTextField` renders a placeholder in the font that was in force when it was *assigned*, so a field whose font has just grown draws its placeholder at the old size — the same trap the search field already had. Set again after the font.
- [x] 6b.5 And the reason the whole pane did not follow: `ChangesPane.applyThemeChange()` existed, did the right thing, and **nothing ever called it**. The sidebar hid that by rebuilding the pane; the page in a tab is not rebuilt, so it never followed at all. Renamed to `applyTheme()` and registered.
- [x] 6b.6 The editor's git change mark had no gap from the line numbers — and worse than none: the bar's position was scaled and the number's right inset was a fixed `gutterPadding / 2`, so the two closed on each other as the zoom rose and the bar drew over the digits above about 1.2×. The mark has its own scaled column now, with the numbers right-aligned against it.

## 7. Finishing

- [x] 7.1 Note in the design what was found out about why `ThemeSwap` did not reach the outline view, or that it was not chased and why.
- [x] 7.2 Check `Scripts/file-size-allowed.txt` for any file this pushed over its aim.
- [ ] 7.3 `make test` and `make warnings`, both clean, both by their exit codes.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the five delta specs in this
change are what it makes true.
