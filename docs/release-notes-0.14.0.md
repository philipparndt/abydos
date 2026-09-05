# Abydos 0.14.0

## A SOPS file decrypts from the status bar

Asked for on 2026-09-04: "when working with sops encrypted files, it would be
nice to be able to decrypt them using the status bar of the editor. We already
support masking secrets from a UI perspective this is similar."

A file with a SOPS extension whose contents carry `ENC[` values and a
top-level `sops` key — looked at once, at open, up to a quarter of a megabyte,
because SOPS writes its block at the *end* of a YAML file — gets a chip beside
the secrets lock: *SOPS · encrypted*. Pressing it runs `sops --decrypt` and
puts what comes back on stdout into the buffer as one edit. The chip then
reads *SOPS · decrypted*, and the values stand revealed with the lock open:
pressing *decrypt* is the explicit act the lock exists to demand, and a
second press to see what was just asked for would be the same question
twice. The lock shuts them at once, and the idle limit shuts them in time,
as for a `.env`. ⌘S, or the chip once the buffer is edited, pipes the buffer
into `sops --encrypt` on stdin under the file's own name — so the project's
`.sops.yaml` rules pick the same keys — and writes the ciphertext over the
file. The buffer then shows that ciphertext again and the chip reads
*encrypted*, so the file can be decrypted again in place; the chip on a
decrypted buffer with no edits puts the ciphertext back the same way, which
is also how a plaintext buffer is put away without saving anything.

**A save that changed nothing writes nothing.** `sops --encrypt` takes a
fresh data key every run, so encrypting a plaintext nobody had edited into
gave the file a new version of the same text — press ⌘S out of habit on a
merely-read file, and every line of the diff changed. The buffer now
remembers exactly what the decrypt returned, and a save over that plaintext
only locks it back: no `sops`, no write, the file keeping its bytes. The
chip, the close dialog and the quit gate take the same path, and an edit
undone back to the decrypt's own text is unchanged the same way a
never-touched buffer is.

**Nothing decrypted touches a disk.** That was the constraint given with the
request, and it rules out both things the tools do: `helmsec dec` writes a
`.dec` beside the original, and SOPS's own editor mode writes a temp file for
the editor. Here the plaintext exists in the document's rope and its undo
stack and nowhere else. Auto-save is off for a decrypted buffer. No language
server hears it — a YAML server would hold it in its own process and its own
cache. The session file records the tab and never its text. The reload on
window focus skips it, and a save over a file that moved on disk since the
decrypt is refused with a toast rather than written over. The driven run's
report says the state, the line count and a digest, never the text.

**Edits survive a project switch, in memory.** A decrypted buffer is parked by
root and file when the window leaves the project — beside the sessions and
the draft inbox, which are the same idea for the same reason — and put back
into its tab when the session reopens the file, edits and caret included. It
is never written into the session on disk, and it lives as long as the app.

**Quitting asks.** With an edited decrypted buffer anywhere in the window,
open or parked, ⌘Q shows *Encrypt and Save*, *Discard*, *Cancel* per file, and
*Cancel* stops the quit. It is the first quit-time gate this app has had;
ordinary unsaved tabs still quit as they always did.

Two things to know. A whole-file encrypt takes a fresh data key, so every
value's ciphertext changes even where its plaintext did not, and the git diff
of a one-line edit is every line — `helmsec enc` does the same today, and
re-encrypting only the changed values needs SOPS's library rather than its
command line. And `sops` runs with the app's own environment: it finds an
`age` key where it always does on this platform, but a `SOPS_AGE_KEY_FILE`
set in a shell profile is not seen by a GUI app.

Driven against the real `sops` 3.13.3 with an `age` key made for the run:
encrypted, decrypted with the plaintext's digest, typed, encrypted and clean,
and `sops --decrypt` at the terminal giving the edited text; a switch away and
back with the edits intact and nothing under the project holding the
plaintext; a missing `sops`, a refusing one, and a file rewritten underneath.
The tool's own times on a 53-value file at load 8 over 10 cores: 0.01 to
0.02 s either way.

## ⇥ follows the file's own indentation, and the footer converts it

Asked for on 2026-09-05: "we should detect if a file is indented by tabs or
by spaces. This should be shown in the editor footer, it should be possible
to switch it. When the file is indented by spaces, and pressing tab we should
insert the right amount of spaces instead." And, the same day: "the
tabs/spaces toggle should be on the right side of the toolbar and it shall
show a menu. It shall then also convert the file when switched."

⇥ used to insert a tab character whatever the file it was pressed in — a
two-space `values.yaml` gained a tab on the line somebody was typing, and
selecting a block and pressing ⇥ indented every line with a hardcoded tab.
Return was the only key that asked the file, and even it took the space
*width* from the tab-display setting rather than from the file, so a
two-space file's new lines indented by the setting's four.

Now the file's habit is a fact about it, read once at open from its head:
which of tabs or spaces begins more of its indented lines — tabs winning a
tie — and, for spaces, the most common run of leading spaces, a tie going to
the narrower, because a continuation line appears once while the step appears
at every level. It is said in the footer on the right, between the caret
position and the language: *Tabs*, or *Spaces: 2* — the file's own width.
⇥, ⇧⇥, a block indent and return's auto-indent all insert one level of it.

**The chip opens a menu, and choosing converts the file.** *Indent with
Tabs*, then *Indent with 2, 4 and 8 Spaces*, with the file's own width
offered beside the standing ones when it is not one of them, and the current
style ticked. The choice converts the buffer's indentation level by level —
one leading tab, or the old width in spaces, becoming one level of the new —
and everything inserted from there follows it. Alignment after the first
non-blank is left alone, a partial level keeps its spaces, and the whole
conversion is one edit: one ⌘Z takes the file back, and the chip goes back
with it.

Two things to know. A file with no indentation yet — a new file, an empty
scratch — falls back to the app's tab width as spaces, which is what return
already assumed. And return's auto-indent changes width in space-indented
files that relied on the setting: a two-space file whose new lines used to
indent by the setting's four now indents by two, which is the point, and is
said here so it is not found as a bug.

Driven on files made for the run. The two-space `values.yaml` reads
*Spaces: 2* with the menu offering Tabs/2/4/8; *Indent with Tabs* converts
every level to a tab and the chip says *Tabs*; ⇥ then inserts a tab, one ⌘Z
takes the tab back and the next takes the whole conversion back — two spaces
again, chip *Spaces: 2*. A tab-indented `Main.swift` reads *Tabs*, converts
to *Spaces: 4* with every level four spaces wide, ⇥ inserts four spaces, and
two undos return it to tabs. A three-space file is offered its own three
beside the standing widths — Tabs/2/3/4/8, *Spaces: 3* ticked. The footer
photographed on the yaml: *1:1*, then *Spaces: 2*, then *YAML*, the chip
between the position and the language where the request put it.

## ⇧⌘P opens where you are looking

Asked for on 2026-09-05: "the agent dialog is opened at the center of the
window when open with the shortcut, which ist nice. I think we should do the
same for the palette (shift + cmd + P)."

⇧⌘A has put the list of running sessions in the middle of its window since it
was added; ⇧⌘P — the same gesture, a key pressed by somebody looking at the
middle of a wide window — opened its list in the top-left corner, because the
key had been handed the geometry of the project pill a *click* opens it from.

Now the key's palette opens centred horizontally on the window that answered
it, near that window's top, as a child of it, in the same panel the sessions
list and the symbol palette use — one placement, written once, rather than a
third copy of the same arithmetic. Escape puts it away, so does clicking past
it, and so does ⇧⌘P pressed again. The list itself is unchanged: the same
rows, ranking, filter field and keys, being one controller in two windows.

A click keeps the geometry a click deserves. The project pill, the branch pill
and the run control still open the list hanging off themselves, with that half
of the capsule lit — a list that jumped to the middle of the window when a
corner control was pressed would have lost the thing it is about.

Driven on a scratch project: over a 1600-point window the palette reports
340×560, centred, 120 points below the top; over a 300-point window — narrower
than the palette wants to be — it stays inside that window's edge rather than
hanging off both; ⇧⌘P again reports it closed; and the same run through the
pill reports the anchored popover with the same 296 rows and the same first
row under ↓.

## Every action in the chrome says what it does

Asked for on 2026-09-05: "we introduced the nice tooltips and hover effect for
the actions in the terminal tab bar. I want the tool tips also for the other
action like: left tool area, project, git, … panel actions, run, debug action.
And I want the hover effect for: project, git, … panel actions, run, debug
action."

The terminal strip's controls have lit under the pointer and explained
themselves in the theme's own type since they were given hover; everything
else was explained by AppKit's yellow box, and two of the three areas lit up
under nothing at all. The rail's tool buttons carried a `toolTip` string, the
project pane's header buttons carried one and drew no hover, and the run and
debug controls registered tooltip rectangles and drew no hover either.

Now the left rail, the project pane's header buttons and the titlebar's run,
debug, chooser and status controls all show the app's own tooltip — a title, a
line of detail where one sentence cannot carry it, and the key in a chip — and
the header and titlebar controls draw a ground under the pointer, the same
rounded band the strip draws. The rail keeps the hover it had, which was
already right. The plumbing behind all four is one type now rather than a copy
per view, and the strip moved onto it too, so a fifth control cannot arrive
with a fifth delay.

**A tip's key comes from the menu bar, not from the control.** That is what
keeps a tooltip's promise and a keystroke the same thing — including when
macOS moves a shortcut it decides is hard to reach on this keyboard. It also
found something: the Run menu declares ⌃R twice, on *Run…* and on *Run*, and a
menu answers a key with its first matching item — so the play button's own
command has no key, and its tip says so instead of claiming one.

Driven: twelve hovers in one run, each saying whether the control lit and what
its tip would tell somebody — the rail's *Project ⌘1*, *Git — 1 commit to
push — ⌘2* and *Terminal ⌘J*, the header's three, the titlebar's four, and the
strip's own *Hide the panel ⌘J* unchanged by the move. Photographed: the
ground under the header's collapse button with the compact pill beside it
untouched, the ground under the ladybird with the play button beside it
without one, and the tip itself — *Debug*, and a ⌃D chip.

## A secret file says whether git can see it

Asked for on 2026-09-05: "a natural extension of the 'secrets' area in the
editor could be to show that unencrypted file containing secrets is not
gitignored", and with it "to initially sops encrypt a matching file (this is
not a warning, just a possibility. For a lot of files the user will not want an
encryption)."

The editor covers a `.env`'s values from the moment it opens, and said nothing
about the far worse exposure: that the file is about to be committed, pushed
and read by everybody who clones the repository. It has the means to know —
the tree asks `git status --ignored` for its tints and the backlog asks
`git check-ignore` for what it writes — and never said.

Now a file whose values are covered is asked about, once when it opens and
again when it is reloaded or the project's git state changes: two `git` runs of
one path each, off the main thread, and none at all for an ordinary file. What
comes back stands beside the secrets lock — *Not in .gitignore*, or *Committed
to git* for the case a `.gitignore` line can no longer fix, since git goes on
tracking what it tracks and the values are in the history either way. Nothing
is shown for a file git ignores, which is most of them, and nothing outside a
repository. It is a statement of fact next to the control it is about: no
dialog, no toast, and the lock still says only what it said.

**The notice is a control.** Pressing it offers to add the file to
`.gitignore` — the file's own path from the repository root, written, said, and
the question asked again so the notice goes by itself. A tracked file's menu
says git already tracks it rather than offering a fix that is not one; the
project tree's *Add to .gitignore…*, where the pattern can be edited, is still
there for everything else.

**And the chip's other side: a plaintext file can be encrypted from it.** Where
a creation rule in the project's `.sops.yaml` matches the path, the SOPS chip
appears on the plaintext file reading *SOPS · encrypt*. Pressing it runs the
same `sops --encrypt` a decrypted buffer's save runs, under the file's own name
so the project's rules pick the keys, and leaves the tab exactly as opening an
encrypted file leaves it. With no `.sops.yaml`, or no rule that matches, there
is no chip and nothing is said — most files are not meant to be encrypted, and
an editor that asked about each of them would be answered by rote. The rules
are read by a bounded line scan for `path_regex`, not by a YAML library: a rule
that cannot be read is a file with no offer, never a wrong one, and `sops`
enforces the real rules when the press arrives.

Driven against a scratch repository with real `sops` 3.13.3 and an `age` key
made for the run: an ignored `.env` says nothing, an untracked one says *Not in
.gitignore*, a committed one says *Committed to git*, and the ignore action
writes the line and takes the notice away. A `secrets/dev.yaml` the rules match
reports the offer, is pressed, and `sops --decrypt` at the terminal gives back
the text that was there.
