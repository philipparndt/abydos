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

## A row says how many subagents are out

A session that has sent work off to subagents looked exactly like one working
alone. Claude Code says so in its own status line; the list that exists to
answer "what is happening where" did not. A row now reads `2 subagents` beside
what the session last said, and says nothing when there are none, because a
count of nought is not news. Typing `subagent` into the filter finds them.

The hook already told us when one finished; it now also sends the tool's name,
so the register can count from both ends — up on the tool use that spawns one,
down when one hands its work back, and back to nought when the turn ends. That
last part is what keeps it honest: a missed event would otherwise leave a count
that only rises. The tool's name is read from the event rather than assumed, so
if Claude Code renames it the count stays at nought and the row says nothing,
which is the safe direction for a guess about somebody else's program.

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

## ⇧⌘A opens the session list

The list of what is running everywhere had one way in: the pill on the terminal
panel's title bar. That means opening the panel first, then aiming at a control
seventy points wide, to ask a question — *is anything waiting for me?* — that is
worth asking at any moment and does not otherwise involve a terminal.

**⇧⌘A** now opens the same list, from `Agent ▸ Running Sessions`, with the panel
closed and nothing to aim at. It comes up centred over the window, near the top,
where every palette in every editor is. Centred over the *window*, not the
screen: this app has more than one, often on more than one display, and a panel
that appeared on the main display when the window was on the other would be
answering somewhere nobody is looking.

It is the same list, not a second one — one filter field, one set of rows, one
set of keys. Type to narrow, ↓ into the rows, ⏎ to go, Escape to put it away,
and a row does exactly what it does under the pill. Opening either route closes
the other, so the list is never on screen twice.

Opening it with nothing running is now a state anybody can reach, and it found
a small fault of its own: the foot's two notes — how many sessions there are,
and what clicking a row elsewhere copies — met in the middle and read as one
sentence. The second is only about rows, so with no rows it is not drawn.

The popover under the pill now says `⇧⌘A` in the corner of its filter row,
dimmed, the way the titlebar capsule says `⇧⌘P`. Somebody who found the list by
clicking is the one person who does not know there is a key for it.

## tmux's windows say what does not fit

The tabs along the bottom of the panel are tmux's windows, and with sixteen of
them in a window that fits seven the list simply stopped at the edge. Reported:
there should be a chevron listing the ones that do not fit, like the other tab
bars have.

It was meant to have one. The strip measures its run, counts what is hidden,
reserves the chevron's room, answers a click on it and builds its menu — on
every strip, tmux's included. Only the drawing sat behind a guard that asks
whether the *panel's* own controls belong here, which they do not on tmux's
strip or in a torn-off terminal window. So on those two the control was
counted, reserved and clickable with nothing drawn to say so: a 34-point
invisible target beside the last window.

The chevron is now drawn on every strip — in tmux's green on tmux's bar, which
it already knew how to do. Choosing a hidden window brings it into view, moving
the run by the least that does so, and the ones now behind are counted with the
ones ahead.

`--tmux-tab-fill 16` fills that strip from a driven run, which nothing could do
before: the mirror is only ever filled by a real `tmux list-windows`, and one of
those does not arrive inside the seconds a driven run lasts. That is why this
shipped.

## The session list keeps its place

Two reports from the first afternoon of ⇧⌘A. The selection jumped about while
the list was open, and reopening the list restored the row it was left on while
the caret went to the filter — a lit row and a live caret both claiming the next
keystroke.

The first cause was a lit row remembered as a *number*. The list is rebuilt on
every hook event and once a second by the staleness clock, and a session
appearing or ending renumbers every row after it, so the selection and the
pointer's own highlight moved to whatever now sat at those numbers — with nobody
touching a key and the pointer perfectly still. Nothing tells a view that the
thing under a motionless pointer has changed, so it never corrected itself
either. Both are now re-found on every rebuild: the selection by the session's
own id, and dropped rather than left pointing at a stranger when its session
ends; the hover from where the pointer actually is at that moment.

**That was half of it, and the report came back twice.** The highlight now
stayed on its own session, and it still moved about — because the rows do. The order is a
good one, where a session is rather than when it spoke, but it is computed
afresh from data that keeps arriving: a session learns its tmux window and
leaves the windowless tail, a session in another project appears and its group
takes its place by name, the mirror seeds a badged window and drops it a second
later. So the order is now decided when the list opens and held while it is
open; a session that starts meanwhile is added at the end, where it can be seen
to have arrived, and reopening the list decides the order again.

One more source of movement went with it: a row can change its *id* without
going anywhere. The register seeds a record for a badged tmux window it has not
heard from, keyed by the window; the moment that session announces itself the
seeded record is dropped and the real one takes over. Held by id alone, that
read as a row leaving the middle and another arriving at the end — at the exact
moment a session starts working, which is when somebody is looking. A row's
place now belongs to its tmux window as well as to the record speaking for it.

And the list keeps a note. Whenever its rows change shape it writes one line to
`~/Library/Logs/Abydos/sessions.log`, and nothing at all while they hold still.

**That note found the actual cause, which none of the three readings had.** It
wrote `rows  -> s s s s s s s s`: eight rows, every id empty. A record seeded
from a tmux window's badge has no session id at all — `isSeeded` is *defined* as
`id.isEmpty` — so everything that told rows apart by id could not tell eight
badged windows apart. The order's final tie-break called every pair of them
equal, and `sorted` is not stable, so they were free to swap on each of the
rebuilds that happen every second. The remembered order remembered one place for
all of them. And "which row is this session on" answered with the first of them,
which is the selection hopping to the top.

A row now has an identity: its tmux session and window while nothing has spoken
for it, its session id once something has — which is exactly what the register
already keys the record by. Six badged windows now come up in window order and
stay in it, with the selection where it was put.

Every session a driven run could put in the register had an id, so no run could
ever have shown this. `--claude-seeded <count>` makes the idless kind.

And the reopened list says where the keys are. A remembered selection is drawn
as a ring rather than a filled band while the filter has the keyboard, and fills
in when ↓ moves into the rows — an outline is a different shape rather than a
different shade, so it cannot be taken for the pointer's hint, which is on
screen at the same time. ⏎ in the filter now acts on the row that is lit, and on
the first one only when none is. The filter takes the keyboard on every opening
with what was typed last time selected, so the next letter replaces it.

## A restored page does not take the terminal's window

Reported: the maximised terminal is lost when switching tmux tabs — and, once
narrowed down, only when the project being switched to has a log or commit view
open.

The chain explains the whole thing. Switching a tmux window moves the shell;
while the window is following its terminal that switches project; a project
switch restores what that project had open, pages included; and every page
opener starts by handing the window back from a maximised terminal. So a
project that remembers a log page took the terminal's window on arrival, with
nobody having asked to look at anything.

That rule is right for the gesture it was written for. While the terminal has
the window the editor is *hidden*, not merely small, so a page somebody asks
for has to take the window or it opens where it cannot be seen. A page being
restored asked for nothing, and now takes nothing: the four openers know
whether they were asked, and only then give the editor the window. Everything
that opens a page on purpose — the sidebar's rows, the Git menu, the review
page — is unchanged.

## A deadline is named, not timed

Three tests kept `make test` red while the code under them worked, and all
three made the same mistake from two directions: they used *how long* a
mechanism took to say *which* mechanism it was, and the suite's own parallelism
decides how long anything takes.

Two of them were already guarded for load and went red anyway — the guard reads
a one-minute load average and is asked before the wait, so the suite's own
parallelism arrives after it has answered. What the run prints now, having
stopped asserting it, is the argument: a one-second deadline firing at 25.0 s
and at 41.7 s, at load 29 and 31 over 14 cores. No midpoint between one second
and two minutes survives that, and both deadlines were working perfectly.

A classification now names its mechanism. The LSP test expects
`.timedOut("textDocument/hover")` exactly — `.notRunning` is checked before the
request is sent and `.failed` carries a reply a sleeping server cannot send —
and the runtime test keeps the reason it already had, `did not answer`, which is
the deadline's own words. Both print their duration with the load beside it
instead of betting on it.

And a test asking a language server for *content* now waits as long as the
machine needs rather than inheriting a typist's ten seconds: `signatureHelp`
takes its own timeout, ten seconds by default for the app, and the test passes
`Patience.seconds` — the number whose own documentation names "a language
server to answer".

`make test` returns 0 at load 25 over 14 cores.

## A picture on the clipboard pastes into the tree

Asked for on 2026-09-03: a screenshot on the clipboard, pasted into the
project tree, as a file. ⌘V in the tree has pasted *files* since item 0436 — a board
that held pixels and no file was, to the tree, an empty board, and Paste stayed
grey over a screenshot taken a second earlier.

Now ⌘V, Edit ▸ Paste and the row menu's *Paste Item* take a board that carries
a picture and no file and write it as a PNG where a pasted file would land:
the selected folder, the folder holding the selected file, or the project root.
A board that already carries PNG bytes is written as it is — the program that
put it there had encoded it once, and `NSImage(pasteboard:)`, the obvious call,
would have re-encoded from a bitmap and could have made it larger. A board with
TIFF alone is decoded and written as PNG, because a `.tiff` in a repository is
a question at review time.

The name is offered, not demanded. The file is written the moment ⌘V arrives,
under the first free `picture-<n>.png`, and the row opens for renaming with the
stem selected: typing replaces it, Escape keeps it. That is not the New File
order, where nothing is on disk until Return, and on purpose — an empty file
Escape left behind is something, but a picture is the thing that was pasted,
and ⌘Z is the answer to a change of mind. *Undo Paste* is what the Edit menu
says, and it moves the file to the trash with the guard every created file
has: one written to since is left alone.

The row is revealed and selected and not opened, on the diagram export's
reasoning: a screenshot is pasted into a project to be referred to from
something being written, and an image tab taking the front would be the paste
stealing that place. Return on the row opens it, as any picture row's does.

Files still come first — a file copied in the Finder can carry pixels beside
its URL, and the file is what was meant — and *Move Item Here* stays a
files-only gesture, since pixels have nowhere to be moved from. Whether Paste
is enabled is read from the board's types, because a menu validates every time
it opens; the bytes are read once, when the key is pressed. A board that
declares a picture and carries rubbish under it writes nothing and says so.

Measured in the driven run at load 3 over 10 cores: a 5120×2880 PNG pastes in
0.031 s, and the same picture as TIFF, decoded and encoded, in 0.135 s. The
run pastes from a board of its own, so proving the gesture never writes the
clipboard of whoever is at the keyboard.

The spec is `pasted-pictures`, new — and the first OpenSpec requirement any of
the tree's file operations have; ⌘C, ⌘V, drop, New File, rename and the
tree's undo stack were built under the old backlog's numbers.

## A picture pasted into a document is a file and a reference

The follow-up, asked for the same day and done the day after: ⌘V over a picture in a Markdown or
HTML document writes it as a PNG into `images/` beside the document — made on
first use — and puts a reference at the caret, `![](images/notes-1.png)` or
`<img src="images/notes-1.png" alt="">`, with the caret inside the empty
description so the next thing typed is the alt text. The file is named for
the document, `notes-1.png` for `notes.md`, because a folder shared by every
document beside it otherwise says nothing about which picture is whose.

Text on the board still pastes as text; the picture path is taken only when
there is none. A language with no picture syntax — pixels into a Swift file —
pastes nothing and greys Paste out, since a file written into the source tree
that nothing references is a stray screenshot in the repository. The file is
written first and the reference inserted second, as one edit: ⌘Z in the editor
takes the reference back and leaves the file, which is in the tree, where the
tree's own ⌘Z removes it. Two undo stacks, and focus decides which, as they
were built to.

**The preview had never drawn a picture.** Foundation's Markdown parser turns
`![alt](path)` into the alt text and nothing else, and only diagrams were
being made into attachments — so every screenshot in every README rendered as
its own description, and nobody had said so. A picture in a document is now
the diagram's attachment cell, fitted to the pane, decoded once per version
of the file so typing beside a 5k screenshot does not decode it on every
keystroke.

Measured at load 3 over 10 cores: a 5120×2880 PNG pastes in 0.010 s, the same
picture as TIFF in 0.121 s.

One thing is left open. What a browser's *Copy Image* puts on the board beside
the pixels was not measured — that copy has to be made by hand in somebody's
browser — so text-first is the rule until the table says otherwise: if a
browser puts the image's address on the board as text, ⌘V pastes the address.
