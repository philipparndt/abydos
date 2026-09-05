## Why

**The terminal strip's controls answer the pointer and the rest of the
window's do not.** The strip's trailing buttons were given a drawn ground
under the pointer and `StyledTip` — the app's own tooltip, themed, three
fields rather than one string — because, as its own comment says, "they had no
hover and no tooltips". Everywhere else the same kind of control is still
either silent or explained by AppKit's yellow box: the navigator header's
three buttons carry `button.toolTip` strings and light up under nothing; the
run and debug controls register `addToolTip` rectangles and light up under
nothing; the left rail's tool buttons light up correctly and are explained by
the system box.

Asked for on 2026-09-05: "we introduced the nice tooltips and hover effect for
the actions in the terminal tap bar. I want the tool tips also for the other
action like: left tool area, project, git, … panel actions, run, debug action.
And I want the hover effect for: project, git, … panel actions, run, debug
action (the left tool area already has hover which matches good for this
area)."

No originating backlog item: asked for directly on 2026-09-05.

## What Changes

- **The app's own tooltip explains every chrome action, not just the
  terminal strip's.** `StyledTip` — one panel, half a second's delay, a title
  with an optional detail and an optional shortcut — is what the left rail's
  tool buttons, a sidebar pane header's action buttons and the titlebar's run,
  debug, scheme and status controls show. The system tooltip they use today
  goes, so that no two controls in the same window are explained in two
  different typefaces.
- **The controls that do not answer the pointer begin to.** A rounded ground
  under a sidebar pane header's button and under each of the run and debug
  controls, drawn as the terminal strip draws it and as the rail already draws
  it — a control that does something when clicked is a control that says so
  before it is clicked.
- **The left rail keeps the hover it has.** It is named in the request as
  already right; it gains the drawn tip and nothing else.
- **What each says is what it does, with its key beside it.** A tip carries
  the shortcut where the action has one — Run's ⌃R, Debug's ⌃D — from the same
  place the menu takes it, so the two cannot drift.
- **Not proposed:** changing what any of these controls do, where they stand,
  or which of them exist; tooltips on rows, cells and fields, which are text
  the pointer can already read.

## Capabilities

### New Capabilities

- `control-affordances`: what a chrome control does under the pointer — the
  ground it draws and the tip it shows, what that tip is made of, and which
  controls owe one.

### Modified Capabilities

<!-- None: the terminal strip's two requirements in `terminal` already say
this for the strip and stay as they are; this change says it for the rest of
the window, which no requirement covers today. -->

## Impact

- `Sources/AbydosApp/Controls/StyledTip.swift` — no longer the bottom panel's:
  a small owner type so a view with several controls can hand the shared tip a
  rectangle and a `Tip` without repeating the timer, the window plumbing and
  the clear-on-exit each time.
- `Sources/AbydosApp/ToolWindowBar.swift` — the rail's buttons drop
  `toolTip` for the drawn tip; the hover they draw is untouched.
- `Sources/AbydosApp/Navigator/ProjectNavigatorViewController.swift` —
  `NavigatorHeaderView`'s three buttons gain a ground under the pointer and
  the drawn tip.
- `Sources/AbydosApp/Titlebar/RunControl.swift` — the run, debug, debug-menu,
  scheme and status rectangles gain a hover ground and the drawn tip in place
  of the `addToolTip` registrations.
- No new dependency, no new drawing primitive: the ground is the tint the
  strip and the rail already use, and the tip panel already exists.
