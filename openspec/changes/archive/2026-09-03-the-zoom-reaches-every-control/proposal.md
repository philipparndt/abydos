## Why

The zoom — ⌘+ / ⌘- / ⌘0, and the separate scale presentation mode switches to —
reaches everything this app draws for itself and almost nothing it asks AppKit
to draw. Anything painted in a `draw(_:)` reads `Theme.current` as it paints, so
it follows; a bezelled control takes its size from `controlSize`, and a metric
copied into a constraint or a row height when a view was built keeps the number
that was true at the zoom in force that day.

Seven reports on 2026-09-01, with screenshots, and they are one fault:

- the log page's search field and its `Whole Repository` / `This File` scope
  control stay at system size beside commit rows that have grown;
- the commit page's `Stage`, `Unstage`, `Draft`, `Commit` and `Push` buttons
  keep their bezel size while the words inside them grow, and the chevron that
  expands the description does not move at all;
- the pull-request review header's `Review…`, `Check Out`, `Hide read`,
  `Whole file` and the two view-mode controls are all at system size, as are
  the list's `Only me` / `My teams too` and the glyph beside them;
- the commit row's height is `Theme.current.scaled(40)` read once when the
  table is built, so at a larger zoom the row does not grow with its two lines
  of text and **the short hash on the second line is clipped** — visible in the
  screenshot as the top third of the hash and nothing else;
- leaving presentation mode leaves the commit page's detail area at the size
  the presentation scale gave it.

`DrawnButton` already contains the diagnosis and the measurement — on macOS 27 a
system bezel is 20 points tall at `.small` and 28 at `.large` whatever size the
font inside it is, so picking a larger `controlSize` only moves the wall from 1×
to about 1.4× — and it was written for exactly this reason. It has two callers.
Every other control in the app is a bare `NSButton`, and there are about seventy
of them.

So the fix asked for is not seventy patches: it is one set of controls that know
about the scale, and the call sites moved onto it.

In the same family, and fixed here: the project tree keeps its dark background
when the palette goes light or presentation mode swaps it.
`NavigatorOutlineView.backgroundColor` and its container's colour are copied in
`loadView()`, and the navigator's `applySettings()` re-applies the row height
and the indentation but never the colours — while the header directly above it
fills with `Theme.current.sidebarBackground` as it draws, and does follow. One
pane, half of it light and half of it dark, in the same screenshot.

There is no originating `.abydos/backlog` item: this comes from direct reports,
2026-09-01, with six screenshots.

## What Changes

- A control library in `AbydosApp` whose members take their font, their
  padding, their corner radius and their height from `Theme.current` and
  re-take them when the scale changes. `DrawnButton` is generalised into it
  rather than copied.
- The members are the shapes the app actually uses: a push button with words, a
  glyph button, a checkbox, a segmented choice, and a search field.
- Every control in the reported panes moves onto the library: the log page, the
  commit page, the pull-request review page and the pull-request list.
- **A control does not have to be told twice.** The library observes
  `.abydosSettingsChanged` itself, so a control is correct after a zoom without
  its owner remembering to re-apply anything. The fault being fixed is
  precisely the one that comes from having to remember.
- Metrics captured at build time are re-applied on a scale change: the commit
  table's row height, the file table's, the constraint constants the panes hold,
  and the commit page's detail area, which is sized in points and must be
  re-divided rather than left where the old scale put it.
- The project tree re-applies its palette: the outline view's background and
  its container's colour follow a theme change the way the header above them
  already does.
- No change to what any of these controls *do*, to the zoom steps, or to the
  presentation scale being a number of its own.

## Capabilities

### New Capabilities

- `scaled-controls`: the control library — what a control takes from the theme,
  when it re-takes it, and the rule that a bezel is never used for a control
  whose size has to follow the zoom.

### Modified Capabilities

- `git-pages`: the log page and the commit page gain requirements that their
  controls and their row heights follow the zoom, and that the commit page's
  detail area returns from a presentation scale.
- `pull-requests`: the review page and the list gain the same requirement for
  their headers.
- `project-view`: the tree's background follows a palette change, which no
  existing requirement states.
- `theme-access`: gains the rule that a colour or a metric copied out of the
  theme when a view is built has to be re-taken when the theme or the scale
  changes — the general form of all seven reports.

## Impact

- **AbydosApp**: a new `Controls/` group holding the library; `DrawnButton`
  moves into it and keeps its callers. `HistoryPane`, `ChangesPane`,
  `PullRequestPage`, `PullRequestsPane` and `ProjectNavigatorViewController`
  change at their construction sites and gain the re-apply path.
- **Tests**: the library's metrics are arithmetic over a scale and are tested
  without a window; the row-height-versus-content claim — that a commit row is
  tall enough for both its lines at every zoom step — is a unit test over the
  nine steps rather than an eye on a screenshot.
- **Driver**: a report saying what a pane's controls measure at a given scale,
  so a driven run can prove the sweep rather than assert it.
- **Cost**: one notification observer per live control, and the same drawing
  the app already does. No bezels means no `controlSize` and no system artwork
  in these panes.
- **Risk**: seventy call sites is a wide diff. The sweep is limited to the
  panes named in the reports; the settings window, the sheets and the pickers
  keep their bezels for now and are named as out of scope in the design.
