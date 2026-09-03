## Context

Four things already know something about running Claude Code sessions, and
none of them knows all of it.

- `ClaudeHookRunner.announce` posts a distributed notification on every hook
  event, carrying `event`, `session`, `cwd`, a `status` derived from the event
  (`working`, `needs`, `done`, or nothing), the tmux `tmuxSession` and `window`
  when the hook ran inside tmux, a `message`, and an `announce` line for the
  events worth a toast. It also writes `@ai_status` on the tmux window.
- `RunningSessions.shared` is fed from that by `ClaudeWatch.handle` and keeps
  **session ids by project slug** — membership and nothing else. Its `note`
  returns a slug only when the answer moved, which is what keeps dozens of
  tool-use events a minute from costing anything.
- `TmuxMirror` reads `@ai_status` and `window_activity` for the windows of the
  one tmux session a window mirrors, and `Window.shownStatus` turns a `working`
  that has been silent for `staleAfter` (30 s) into nothing. `PanelTabStrip`
  draws that as a badge, with a spinner timer that runs only while something
  is working.
- The navigator's `Claude Sessions` root lists the sessions of the window's
  project and knows how to copy `claude --resume <id>`.

The panel strip's trailing controls are placed backwards from its trailing
edge: hide, maximise, follow, then the `tmux · session` tag, whose click
callback `onMirrorTagClicked` hands the tag's frame to the panel so a menu can
be anchored to it. The pill goes to the left of that tag and is anchored the
same way.

The comparison of placements, and why the pill was chosen over a rail button,
a strip segment, a navigator node, a switcher column and a corner strip, is in
the proposal and at the artifact it links.

## Goals / Non-Goals

**Goals:**

- From across the room: how many sessions are working and how many need input,
  anywhere on the machine, in the colours the tab badges already use.
- One click: every running session, grouped by project, with what it last said
  and how long ago, and a way to get to it.
- Nothing on screen when nothing is running.
- Nothing read from disk and no process asked, per event or per redraw.

**Non-Goals:**

- Naming the model a session runs. The hook does not carry it, and the mockup
  that showed it was wrong to.
- Killing, pausing or answering a session from the popover. A row gets you to
  the terminal; the terminal is where the session is driven.
- A second vocabulary. `working`, `needs`, `done` and the 30‑second staleness
  are the tabs' and are reused as they are.
- Showing sessions that ended. The navigator's root is where what a session
  left behind lives.
- Sessions from other machines or other users. The distributed notification is
  per machine and per user, and so is the answer.

## Decisions

**The register remembers what each session last said, not just that it exists.**
`RunningSessions` gains a per-session record — status, tmux session and window
when given, last announced line, time of the last event — replacing the bare
`Set<String>` per slug. `ids(forSlugs:)` and `belongs` keep their meaning.

*Ruled out: reading `@ai_status` from every tmux server on the machine.* That
is one `tmux list-windows` per socket per redraw, it says nothing about a
session outside tmux, and it cannot say what the session last said. The tabs
read it for the one mirrored session because that is the session they draw.

*Ruled out: reading transcripts under `~/.claude/projects`.* A modification
time is a guess about attention, which is the exact thing `RunningSessions`
exists to not be, and a day's transcript is twenty megabytes.

**`note` returns a slug whenever the shown answer moved, and still nothing for a
tool-use event that changes nothing.** Today it answers "new session", "ended",
"turn finished". A change of status — `working` to `needs`, `needs` back to
`working` — moves the pill's counts and now returns the slug as well. A
`PostToolUse` from a session already `working` still returns nil, which is the
test `aToolUseFromAKnownSessionAsksForNothing` and the property that makes
this affordable. The pill redraws on a returned slug; the navigator keeps
refreshing on the same signal and is not told anything new.

*Ruled out: a second callback for status changes beside `sessionsChanged`.*
One event, one answer to "did anything move"; two callbacks would be two ways to
get the answer half right.

**Staleness is the tabs' rule, applied to the register's clock.** A record whose
status is `working` and whose last event is older than
`TmuxMirror.Window.staleAfter` is shown hollow, labelled by its last line and
its silence, and counted under neither number. `staleAfter` becomes the shared
bound rather than a `Window` detail. The pill re-evaluates on a one-second
timer that exists only while at least one record is `working`, in the manner
of `PanelTabStrip.syncSpinner`: an idle app is an idle app.

*Ruled out: `silentFor` from tmux.* The register has no tmux for a session
outside one, and it has the time of the last hook event for every session,
which is the same fact measured at the source.

**Counts are working and needs; done is listed and never counted.** A finished
session waits quietly and raising a number for it teaches the pill to be
ignored. Amber is the only state that earns colour on the chrome.

*Ruled out: three counts.* The mockup with three read as a dashboard; the
question the pill answers has two parts.

**Absent when idle, not empty.** With no records the pill has no frame,
`layoutTrailingControls` does not reserve for it, and the tabs get the room
back. The alternative, a grey `0 · 0`, is furniture — the same reasoning as the
`Fetch` control not being drawn where there is no remote.

**The popover is a list, drawn from the register and grouped by slug.** The
window's own project's slugs come first; other groups are ordered with the
most recent event first. A group is titled by the last path component of the
`cwd` and subtitled with its parent, home‑relative, because a slug is not a
name. A row shows the badge, the tmux window name and index when the record
has them or the last line when it does not, the last announced line
underneath, and the age on the right.

**A row does what the nearest existing thing does.** A row whose `tmuxSession`
is the window's `mirroredTmuxSession` calls `revealTmuxWindow(index)`, which is
the toast's action. Any other row copies `AgentSessions.resumeCommand` to the
pasteboard and says so with the toast the navigator uses. Both paths exist and
are tested; the popover adds none.

*Ruled out: switching the mirrored tmux session from a row.* That changes what
the whole panel shows, and the mirror tag's menu is the place that already
offers it. Left open below.

**Seeding from the mirrored tmux session.** A session that was running before
the app launched has announced nothing to this process. The hook's tool-use
events arrive dozens of times a minute for a working session, so it appears
within seconds on its own; a session sitting at a prompt does not. For the
windows this window mirrors, `TmuxMirror` already reads `@ai_status` and
`window_activity`, and a window that has a status and no record in the
register gets a record with no session id — enough to count and to reveal, and
replaced by the real one at the next event. Outside the mirrored session
nothing is seeded, and the proposal says so plainly.

*Ruled out: a `SessionStart`‑style scan at launch.* There is nothing to scan
that says *running*; that is the whole case for the register.

**Drawn with the shared control library.** The pill is a `DrawnButton`-family
control, scaled by `Theme.current.scale`, so it is not born unscaled — this is
why the change depends on `the-zoom-reaches-every-control`. The tmux tag's
`mirrorTagText` shortening rule (the name drops when the strip is under 420
points) is matched: under that width the pill shows its two dots and drops the
digits.

**Driving it.** `--claude-running <id>[@<seconds>][:<status>]` — the status
suffix is new and defaults to `working`, and the option may be given more than
once, each on the same project, so a popover with rows in more than one state
can be photographed. `--claude-running` on another path than `--open` is what
makes a second group. The pill's counts and the popover's rows are reported
through the driver like the toasts are. A driven run still never subscribes
(`ClaudeWatch.listensOnThisRun`).

## What implementing it found

**The one callback did not survive, and the reason is worth keeping.** The
decision above says `note` returns one slug and both the tree and the pill
redraw on it. The existing test `aToolUseFromAKnownSessionAsksForNothing`
showed why that cannot be: a session's first tool use takes it from *started* to
*working*, which moves the pill's count from nought to one and changes nothing
under the tree's row — and the tree's redraw is a walk of a scratchpad. So
`note` returns `Moved`, carrying the slug and whether the *sessions* changed;
`ClaudeWatch` tells the tree only when they did and the pill on every move.
Still one event, one answer; the answer has two parts because two things read
it.

**The pill is drawn by the strip, not built as a control.** The tmux tag beside
it is drawn inline in `PanelTabStrip`, reading `Theme.current.scaled` where it
is used, and that is exactly what the drawn-control library does — so the pill
is drawn the same way and scales for the same reason, without a view of its
own to lay out. The dependency on `the-zoom-reaches-every-control` is kept for
the principle, not for a class.

**The controls live on the top strip.** When tmux's windows get a strip of
their own along the bottom, the panel's controls — and so the pill — are on the
strip above it, beside the `tmux` tab; the green strip carries the badges and
nothing else. The mockup had that right and the proposal's wording did not
distinguish them.

**A seeded record has to be forgotten as well as made.** `seed` drops what the
mirrored session no longer badges, but nothing reads a session the panel has
stopped mirroring, so its seeded records would have stayed for good. The panel
forgets them when the mirror moves to another session or ends.

**A tmux session is a workspace, not a project.** The seeding decision above
files a seeded record under "this window's project", and the first afternoon
showed `2 screencasts` under `abydos ~/dev/oss`: the person's `abydos` tmux
session holds windows for nine directories across three parents. tmux knows
each pane's directory — `pane_current_path` — so `TmuxMirror.Window` carries it
and a seeded record is filed under it, and the "only project the panel can
name" reasoning was simply wrong: tmux could name them all.

**The popover is a window of its own, and so is its picture.** A driven
screenshot draws the window's view tree; an `NSPopover` is a child window and
comes out beside the capture as `-child0.png`, the way a sheet already does.
The screenshot script says so where it takes the shot.

**The length ratchet decided where the code lives.** `BottomPanel.swift`,
`AppDelegate.swift` and `LaunchOptions.swift` are on the list of files that may
not grow, and the first cut grew the panel by 257 lines. So the pill's
measuring and drawing is `SessionsPill`, and the clock, the popover and what a
row does are `PanelRunningSessions`, an object the panel hands three closures
to. What remains in the panel is what only the panel can hold: the strip's
frame for a new control and where it is laid out and hit, and the wiring. The
three recorded lengths go up by 76, 23 and 26 lines for that — the strip's own
control, the driven-run seeding in both of its moments plus two reports, and
the flag grammar — and `Scripts/file-size-allowed.txt` carries the new numbers.

**Working is grey.** The tabs draw a working badge in the sidebar's text colour
at half strength, not blue; the pill uses the same, and the mockup's blue was
the mockup's.

## Risks / Trade-offs

**Two windows on two projects both show the same machine-wide pill** → That is
the point: the pill answers for the machine. Only the grouping order differs.

**A session that never announces is invisible** → Only a session that started
before the app and has been waiting since, outside the mirrored tmux session.
It appears at its next event; its `SessionEnd` is what removes it, and a
session killed mid-turn leaves a `working` record that goes hollow after 30 s
and is removed when it has been hollow for a bound to be chosen in the tasks.
Left open below.

**The strip is already crowded on a narrow panel** → The pill is placed before
the tag in the same backwards layout, so it is the first thing the tabs meet
and is covered by the ground requirement the terminal delta names. Under 420
points it drops its digits, as the tag drops its name.

**A one-second timer while anything is working** → Redraws one control, only
while a working record exists, in the same shape as the spinner timer that is
already running whenever a tab spins.

## Open Questions

- ~~How long a hollow record lives.~~ Decided in the code: a working record
  silent for ten minutes is forgotten (`RunningSessions.forgottenAfter`), and
  `aWorkingSessionSilentForTenMinutesIsForgotten` pins it. A waiting or
  finished session is never forgotten this way.
- **Whether a row outside the mirrored tmux session should offer to switch the
  mirror.** The mirror tag's menu already does this; the row could carry the
  same verb on its context menu. Not decided; the first version copies the
  resume command and nothing more.
