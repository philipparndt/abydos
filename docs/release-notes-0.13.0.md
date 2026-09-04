# Abydos 0.13.0

0.12.0 went out on the morning of 2026-09-04, and the same day brought eight
reports, most of them from somebody using the app and saying exactly what they
saw. This release is those, and nearly every section below opens with the
sentence that started it.

Two of the reports were written up as changes before 0.12.0 was cut and are in
this release rather than that one — the commit draft and the trashed row — so
their notes are here, where the code is, and not under the version whose
image was built before them.

## The panes keep their folds, and the session keeps the shape of the window

Reported: "we should keep more track of the UI status in the session. For
example: the git panel 'Working copy' section is always collapsed when
returning (and many more)."

The example was exact and the cause worse than "at quit". Every fold set in
this app lived on the view that drew it, and the sidebar tool is thrown away
and rebuilt on a project switch, a second or two after a window opens when
reading the repository lands on a different work tree, and when a tool shown
over the terminal is put away. So the working copy re-folded under somebody
who had unfolded it thirty seconds earlier. The comment beside that rebuild
already named both halves of the loss — "it took with it the commit message
half typed into the pane and the folders unfolded in it". The message half was
fixed in 0.11; this is the folders half.

A project's session now carries, in the file beside the project:

- **What was folded in each tree** — the refs tree, both sides of the changes
  tree, and the project tree. Two lists per tree rather than one, because the
  trees disagree about what an absent key means: a refs tree arrives open and
  records what was *shut*, while `origin` and `Tags` arrive shut and record
  what was *opened*. Applied where each pane is built, not once after a load,
  since the first rebuild would undo that.
- **Which sidebar tool was in front**, falling back to the project tree where
  the remembered one cannot be built. It does not open a sidebar somebody
  closed.
- **Which terminal was in front.**
- Arrival defaults are untouched for a project nothing was recorded for, and a
  session file written before any of these keys existed still reads.

And two pages the session had always written and nothing ever read: `launch`
and `settings` went into every session file and came back from none. They
come back now.

Two driven runs caught faults before they shipped. Capturing the panes' fold
*sets* recorded what somebody decided and left the outline to hold the rest,
so a tree came back more unrolled than it was left; the capture walks the
rows now. And the terminal in front was matched by name, and three terminals
are all called `Local`; the session object is held as it is created instead.

## The strip's controls answer the pointer, and say what they are

Asked for, with a picture of the terminal's title bar: "what is gray/orange
on the agents element, what is the agents element even."

The sessions pill was two coloured dots and two figures, and nothing on screen
said what they counted. And half the strip answered the pointer while the
other half did not: the tabs had had a hover since they were drawn, the
controls beside them never did.

Every trailing control lights up under the pointer now, in the tabs' own
shape — and twice as much for the pill and the `tmux · session` tag, which are
drawn on a tint of their own and swallowed the plain band. That was found by
cropping the same region from a hovered and an unhovered run rather than by
assuming: a chevron on this very strip was computed, reserved, clickable and
never drawn earlier in the week.

Each control says what it is. The pill: what the two colours count, that a
finished session is in neither, and that ⇧⌘A opens the list. The tag names
the tmux session and what clicking it does; the rest say their verb and the
key that does it.

**And the tips are drawn, not AppKit's.** Asked the day after: "the tooltips
are currently plain text, think we can make them nicer." A system tooltip is
one paragraph in one weight in a yellow box that belongs to no theme here,
with the shortcut sitting in the prose as though it were a word. A tip is now
three fields — a title in the text ink, a detail dimmed and wrapped, and the
key as a rounded cap at the trailing edge — in the app's own floating panel,
the one the parameter hints already use. It follows the hover rather than a
tooltip rect, since the strip's controls are drawn and have no views: shown
half a second after the pointer rests, gone on exit, on any press, and when
the strip leaves its window. Nothing else in the app changes its tooltips; a
label on a button is a label.

## The follow switch is remembered

Reported: "when installing a new version the link terminal / project setting
is always disabled."

Not the installing. The switch on the panel flipped the window's own copy and
never wrote the preference, so the two ways of turning following on
disagreed: the checkbox in Settings persisted and the control anybody reaches
for did not. Every launch read the stored `false`; a new version is simply the
launch somebody notices. The switch writes it now, and a window adopts a
*changed* preference — not every settings change, or a font slider would undo
a window's own answer, and the per-window switch is deliberate.

## A draft finds its project, and is offered rather than thrown away

Reported: "as soon as the project is switched to continue the work on something
else in the mean time, the commit comment is not written back to the right
project. The user is forced to stay on that page. Also when there is already a
commit comment there, the draft result is just thrown away. Would be better to
have the option to use this then."

A draft takes a while, and its answer had nowhere to land but the pane that
asked for it — a view that is neither long-lived nor tied to a project. The
sidebar's changes pane is rebuilt whenever the tool is; a project switch closes
the commit page's tab and rebuilds the sidebar only once the new project's
branch read finishes. So a draft that came back after a switch was lost one of
two ways: the pane had gone and the answer was dropped without a word, or the
pane still on screen was the *old* project's, took the draft, and the next
session save wrote one project's words into another project's file.

A finished draft now goes to an inbox keyed by repository root, kept beside the
per-project sessions the window already holds. A pane applies what is waiting
only when the draft's root is its **own** — not the window's current project,
which is already the new one while the old pane is still on screen, and that gap
is exactly where the fault lived. Coming back to the project picks it up, from
either the sidebar or the commit page. Nothing is written into another project's
message.

And a draft arriving onto a message with words in it is offered instead of
discarded. Both fields empty: filled, as before. Either field with text: the
draft is held, the button turns red and reads **Use draft instead**, and
pressing it replaces both fields — whole, the way choosing from the history
already does. Typing on leaves the offer standing; committing clears it.

That fixes a quieter fault in the same place: the two guards were independent, so
a typed subject over an empty body took the draft's *description* and dropped
its summary — a message nobody wrote.

The button has three states now — *Draft*, *Drafting…* with the spinner Push has
always had, and *Use draft instead* in red — driven by one enum rather than by
comparing its own label. That comparison was why a relabelled button quietly
stopped having its availability and tooltip refreshed, and why two of the three
failure paths left it disabled saying "Drafting…" for ever.

A commit page left over from another project is no longer reused for this one:
it was being handed this project's remembered message and this project's draft.

## A trashed row goes at once

⌘⌫ used to do nothing visible for as long as the trash took to answer. The row
left when the file-system watcher noticed the file had gone from its directory —
after a cross-process round trip of hundreds of milliseconds, and after up to a
quarter-second of event coalescing if anything else on the machine was writing.
Reported on 2026-09-04: "when deleting files it takes long till the project view
refreshes and removes the file. Sometimes it takes so long that the user tries
again and gets an error message."

The row now goes in the same event as the key, before the trash is asked, and the
selection lands on the row above it as it always did. The trash's answer is still
what ⌘Z remembers, because the dictionary it returns is the only place the trash
location of each file exists — a file the trash renamed on collision comes back
under its own name. What changed is what is on screen while that answer is
awaited.

The error message was the second press. `⌘⌫` never checked the file was still
there, handed the dead URL to the trash again, and the toast said *Could not move
that to the trash* over a file that was already in it. A row whose file has gone
is no longer sent to the trash: its folder is re-read instead, which is the honest
reply to a stale row however it went stale — a file deleted in a terminal reaches
the same place.

And the "sometimes" had a cause of its own. A trashed **folder** arrives from
FSEvents as a must-scan event naming that folder, and the watcher re-reads only
directories the tree has listed — so a folder nobody had ever expanded kept its
row until something else changed its parent. The trash now re-reads the parents
of what it moved, so that row goes whether the watcher notices or not. The
watcher's own rule is unchanged: it is right for files written by something else.

If the trash refuses a file, its row comes back beside the toast saying why, and
whatever it did move stays gone.

## Fetch is not offered twice, and a branch can be rebased on

Two reports about the refs pane.

"Two fetch buttons but no pull button?" The row's verb is chosen from the
current branch's state — Pull when behind, Push when ahead, Fetch otherwise —
and a second `Fetch` sits beside it so that the word never disappears. When
the first verb *is* Fetch, the two were drawn side by side saying the same
thing. The duplicate is dropped where the first verb is decided, so it comes
back the moment that verb is Pull or Push. The `↓2` in the picture was
`main`'s own row, which is where a pull for main belongs.

"We do not yet have a rebase on action in the menu here." There was no rebase
anywhere. The branch menu gains *Rebase on <name>…* beside *Merge into
Current*, named for the row it hangs off because that row is the destination:
right-clicking `main` puts the current branch on top of main. It asks first,
where merge does not, and that is not an inconsistency — a merge adds a commit
that can be dropped, a rebase rewrites every commit on the current branch. No
`--autostash`: git refuses on a dirty working copy and the pane says so, which
is better than stashing somebody's work and handing it back mid-rebase. A
conflict leaves the repository mid-rebase, which the conflict list already
reads.

## The status bar switch says whose bar it takes

Reported: the help for *Hide tmux's own status bar* says nothing else is
harmed, and the session being used loses its status line.

The words were "Set on the session as it is attached — nothing is written to
~/.tmux.conf, and other sessions keep their bar." Every clause true, and
together they read as "this does not reach my tmux elsewhere". It does: the
switch sets a session option, and a session option belongs to the session and
not to this app's client. Every terminal attached to that session draws no bar
either, inside Abydos or not, then and later, and nothing puts it back when
the app quits — only turning the switch off does, which restores whatever that
session's own configuration says.

The help leads with the reach and ends with what is spared. The two toasts
differ, since restoring is not the mirror image of hiding. No behaviour
changed. And a help text can now be read back from a build, which is how a
wrong one survived to be reported from outside: `--settings-says` prints a
row's title and help.

## A test that asserted the machine

One of the dependency tests failed on a clean tree in 22 milliseconds, so
`main` was red for whoever pulled it. It compared whole values, and the
reader legitimately resolves a jar from the developer's own Gradle cache when
the version happens to be in it — so what the test asserted was a property of
`~/.gradle`. It asserts the names, the versions, the origins, and that nothing
is a local path, which is what it was about.

`make test` on this tip: 4061 tests in 517 suites, exit 0, at load 30 over 10
cores; `make warnings` exit 0. Both by their exit codes.
