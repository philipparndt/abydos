# Abydos 0.12.0

Every Claude Code session on the machine already told Abydos what it was doing:
the hook posted an event for each of them, the tmux tabs wore a badge for the
session in them, a toast said a line when one in another tab spoke. What none of
it answered was the question asked from across the room — *is anything waiting
for me, and where?* The tabs knew only the one tmux session the window mirrored,
the toast was gone in seconds, and the tree's `Claude Sessions` root listed one
project and was usually scrolled away.

The request was for an overview of all running sessions, 2026-09-02, and six
places for it were drawn against the real window before one was chosen. This
release is that one.

## The terminal's title bar counts the running sessions

Left of the `tmux · session` tag on the terminal panel's title bar there is now
a pill with two numbers: how many Claude sessions on this machine are
**working**, and how many **need you** — in the colours the tab badges already
use for the same two states. A finished session is not counted, because it
waits quietly; a working session that has said nothing for thirty seconds is not
believed, which is the rule the tabs' spinner already follows; and when nothing
is running there is no pill at all, so an idle panel looks as it did.

Click it and every running session drops down, grouped by project with this
window's project first: the tmux window it is in when the hook could say, its
last announced line, and how long ago that was. A row in the tmux session these
tabs mirror opens that window, as the toast's action does. Any other row copies
`claude --resume <id>`, as the tree's session rows do, because the way back to a
session this panel cannot show is the command that resumes it.

Two limits, said plainly. The hook carries no model name, so the list does not
show one. And a session that started before Abydos did, and has sat at a prompt
since, has announced nothing to this run of the app: it appears at its next
event. For the windows the panel mirrors, tmux's own `@ai_status` stands in
until then, so those are counted from the start — and filed under each pane's
own directory, which tmux knows, because a tmux session is a workspace whose
windows sit in many projects. The first afternoon had `screencasts` under
`~/dev/oss` for want of asking.

The register behind it, `RunningSessions`, now remembers what each session last
said rather than only that it exists. Nothing reads a disk or asks a process for
any of this, and the pill redraws only when the two numbers move — a working
session's tool-use events, dozens a minute, still cost nothing.

The spec is `running-sessions`, new; `terminal`'s requirement that the panel's
controls are drawn on a ground of their own names the pill among them.

## A row reaches every terminal it can

The list came back from its first afternoon with three notes. It was wasteful
in height; a row reached only the tmux window the panel mirrored, and only
while the `tmux` tab was in front; and a session in some other program's
terminal looked exactly like one in the tab next door until it was clicked.

Every terminal the panel starts now tells its shell which tab it is, as
`ABYDOS_TERMINAL`, beside the `TERM_PROGRAM` it already sets rather than
inherits, and the hook passes that on — or, inside tmux, the pane's own id. A
row then reaches everything the app holds: the tab the session named, in this
window or another; the window and pane of the mirrored tmux session; another
tmux session, by switching this panel's client to it or attaching a `tmux` tab
when there is none. A session the app cannot reach is drawn dimmed and marked
*elsewhere* before it is clicked, and clicking it copies the resume command, the
one thing the app can offer for a session it does not hold.

And the list is a list: one line per row, a filter field that narrows the rows
as it is typed into and chooses the first match on ⏎, and a scroll inside a
bounded height, so a dozen sessions are a dozen rows.

## A nudge does not wake a finished session

The pill found a fault the toast had been making quietly for as long as the
hook has run outside tmux. Claude Code sends a `Notification` about a minute
after every finished turn — "Claude is waiting for your input" — and for a
session in tmux the hook reads the window's badge, sees `done`, and ignores it.
For a session in one of the panel's own terminal tabs the hook has no window to
ask, took the nudge for a question, and said "needs you" over an empty prompt.

The hook's payload now carries the notification's type, and the register —
which held the session as `done` from its `Stop` — applies the hook's own rule:
nothing resurrects a finished turn. The row stays a tick, the pill does not turn
amber, and the corner says nothing. A real question after a finished turn, a
permission prompt say, still comes through; so does a nudge for a session that
was working when it arrived, because that one is Claude paused for an answer.

`running-sessions` gains the requirement.

## A glyph that spills into the next cell survives it

Running the test suite in a pane drew swift-testing's marks as their left
halves — a filled triangle where Ghostty drew a diamond with a tick. The marks
are SF Compact symbols nearly two cells wide, and the GPU renderer already let a
glyph reach past its cell; what it did not stop was the next cell, drawn a
moment later in the same pass, painting its background over the overhang. The
CoreGraphics renderer never had the fault, which is why it took the drawable
itself, not a screenshot, to see it.

The cells are now drawn twice from the one buffer: every background inside its
own cell, then every glyph over all of them — each glyph in a box of its own
cell's colour, the full height of the row and as wide as the glyph reaches, so a
black diamond on a yellow prompt segment stays black on yellow into the cell
beside it rather than turning black on black there.

## One tree behaviour, in all four trees

The behaviour the changes tree gained in 0.11.0 — a selection held across a
rebuild, and landing on the nearest surviving row with a word in the log when
its row has gone — is now the branches tree's and the file lists' too. The
branches tree had kept its selection by key across a rebuild and lost it on a
push, a publish, a deletion and a theme change; the log page's and the pull
request's file list kept it across a rebuild and lost it when the line counts
landed a moment later. All four trees were driven the same way on the same day:
click a row, the tree has the keyboard, the arrows move, ← and → fold and open
without losing the row, and a rebuild keeps it.

## Blue is the default again

A fresh installation opens in the blue theme. It had opened in `abydos` for a
while, and every current user chose blue over it; a default nobody keeps is a
first-run chore. What a stored choice means is untouched.

## The backlog pane stays under the tab strip

Reported on 1 September with a screenshot and the word *sometimes*: the pane's
`List` / `Board` control sat under the `tmux` tab and its `Refresh` under the
strip's controls. It was not the panel placing the pane, which a measurement on
four routes showed exactly below the strip every time. The pane's header had two
rules for its height: on load it stayed for a project with a backlog *or*
OpenSpec changes, and on every zoom, theme or presentation change it stayed only
for a backlog. This project moved its work to `openspec/changes` on the day of
the report, so the first zoom after opening the pane collapsed the header to
nothing — and a stack view of no height does not clip, so its controls drew
around the pane's top edge, into the strip. One rule now, and a header with
nothing to say is hidden whole.

## The session list answers the arrows

The popup opened with the keyboard in its filter and there was no way out of the
field but the mouse. ↓ now moves into the rows with the first selected, ↓ and ↑
move between sessions and skip the group headers, ⏎ opens the selected one, and
↑ from the top hands the keyboard back to the filter with the caret at the end
of what was typed — so narrowing and choosing are one movement in each
direction. Escape puts the list away from either place.

A selected row is drawn in the palette's selection colour and a row under the
pointer in the hover tint, because they answer two different questions: which
row a key will act on, and where the mouse happens to be.

## The session list holds its order

The rows jumped around. Three things ordered by something that keeps changing —
the groups after the first by their most recent event, the rows without a tmux
window by theirs, and ties by nothing at all, so a dictionary's walk order
showed through an unstable sort. The list is rebuilt on every hook event and
once a second by the staleness clock, so all three moved dozens of times a
minute while anything was working, and a row that moves while you are reaching
for it cannot be clicked.

Order now follows where a session is, never when it last spoke: the window's own
project first, the rest by name, and within a project the tmux session's name,
the window's index, then the sessions in no window. Every comparison ends in the
session's own id, so nothing can be called equal and swap on a redraw. Recency
was a deliberate decision when the list was written and it was the wrong one: a
sensible order for a list read once, a hostile one for a list that redraws while
somebody reaches for it.

## The session list turns while a session works

The tmux tabs have turned a spinner for a working session since the badges were
added: a still `⋯` says "something is happening here" no more convincingly than
a full stop does. The running-sessions list drew that still `⋯` for the same
state one panel up, so the pill counted a session as working while the row
beside it looked asleep. Both now draw one shared arc, each on its own timer
over its own rows, and each timer exists only while something is turning.

## A picture diffs as a picture

A changed screenshot, icon or exported diagram used to diff as one line: **No
textual changes.** True, and useless. Wherever a diff is shown — the commit
page, the log page, a pull request — a file the app already opens as a picture
is now read from git as its two sides and drawn on the same checkerboard the
editor uses, each side labelled with what it is and its pixel size.

Three ways to look, on a switch above the pictures, and the choice is
remembered. *Side by side* puts the two at one scale. *Slider* lays them over
each other with a divider to drag. *Changes* dims the new picture and outlines
the regions that differ from the old, with a count. The comparison is
arithmetic in the kit, tested without a window: a channel threshold so a
re-encode is not a change, differing pixels gathered into rectangles, and a
plain refusal with a reason for two pictures of different sizes or one too
large to compare. An added or deleted picture shows its one side and says so,
and the two comparing modes step aside for it.

## A pane keeps the app's environment

A pane that named itself to its shell — the tab identity the running-sessions
list reaches by — was starting that shell with *only* that variable: passing an
environment replaced the app's rather than adding to it. A login shell rebuilds
enough from the profile that panes still worked, which is why it took two
screenshots to see. A prompt drew a user segment nobody had asked for, because
the rule that hides it reads a variable that was no longer there. What is given
is added now, and a test says so.

## The pill believes a working session for longer

A session that was working showed as silent after thirty seconds, and the pill
read `0 · 0` over a list of sessions plainly at work. Thirty seconds is the
tabs' rule and right for them: they go stale by any byte printed in the pane,
and Claude prints a spinner while it works. The register's clock is the last
hook event, and hook events bracket a tool call — a `make test` is ninety
seconds with nothing in between. Ten minutes now, and an hour before a session
is forgotten outright.

## Next Tab follows the keyboard

⌘⇧] and ⌘⇧[ used to move the editor's tabs wherever the keyboard was, so pressed
in a terminal they changed the file behind the panel, and the panel's own strip —
the `tmux` tab, the `Local` terminals beside it — had no keyboard route at all.
tmux's windows could be walked with tmux's keys; the tab next to them could not
be reached from them, or come back from.

With the keyboard in the panel the two keys now move along the strip of the
column being typed in, wrapping, and take the keyboard with them, exactly as a
click on the tab would. In the editor they do what they always did. Where tmux's
windows have their own strip along the bottom, the top strip's tabs are what the
keys mean and tmux keeps its own; a top strip holding only `tmux` cycles the
windows instead.

`terminal` gains the requirement, and `tab-overflow` no longer says the strip
has no keyboard route.
