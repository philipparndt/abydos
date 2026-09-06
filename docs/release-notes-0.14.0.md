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

**The panes too, once they were asked for.** A pane's buttons are not the
window's chrome, so the first cut left them: the git panes' *Commit*, *Push*
and *Draft*, the review page's *Check Out* and *Review…*, the pull-request
refresh, the scratches pane's two and the debug console's clear. They now
carry the same tip, and light under the pointer — `DrawnButton` had hover
state and drew it only for its quietest buttons, so the loud ones never
answered at all. The scratches and debug buttons stopped being system bezels
on the way, which also settles their height at a large zoom.

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

## A tag can be deleted, here and on the remote

Asked for on 2026-09-06: "it should be possible to delete tags (+ remote
tags)."

The engine has been able to do this since tags learnt to move — `GitTags`
deletes locally and on the remote, fully qualified as `refs/tags/<name>`
because `git push origin :v1` is ambiguous when a branch shares the name — and
nothing in the window called either. The tag rows offered *Recreate…* and the
forge, so getting rid of a tag meant a terminal, while the spec had said for
months that a tag could be made, moved and deleted.

A tag row now offers *Delete Tag…*, for one tag or several, and ⌘⌫ does the
same from the keyboard — this app's delete gesture, which the project tree has
trashed files with since it had a tree. Branches keep their menu-only delete on
purpose: theirs asks about worktrees and about commits nothing else has, and a
bare key is too small a gesture for that question. A selection holding a branch
and a tag together is two different questions, so the item is shown disabled
rather than acting on half of it.

**The remote is a separate tick, off by default, named after the remote.**
*Also delete on `origin`* — because a fork and an upstream are both plausible
and a sheet that made somebody remember which is a sheet that gets the wrong
answer. Locally a tag is a name for a commit and can be written again while
that commit is there; on the remote it is what a workflow, a release page and
everybody else's fetch read.

**And each half is reported in its own words.** The local delete runs first, so
a remote that refuses — a protected tag, no permission, no network — leaves the
tag gone from the tree in front of you and says *Deleted here, still on origin*
with git's reason under it. One "could not delete" over a half-done pair is the
sentence that sends somebody to a terminal to find out what state they are in.

Driven against a scratch repository whose `origin` is a bare repository beside
it: a tag deleted locally with `git ls-remote` still showing it; the same tag
taken from both; two at once; a mixed selection disabled; a repository with no
remote offering no remote choice; and a broken `origin` proving the half-done
report.

## A project is trusted before it runs

Asked for on 2026-09-06: "abydos shall have a untrusted mode, where no code
from downloaded projects is executed, like devcontainers. VSCode does something
similar." — and, before it, the sharpest case: "in the untrusted mode, also
setting environment variables must not be possible (think of setting
SOPS_AGE_KEY_CMD)".

Opening a folder here used to run code from it. Not on a press — on the open:
run configurations are discovered by reading a `Makefile`, a `launch.json` and
a devcontainer definition; a language server is started from what the project's
tree provides; a terminal comes up in its directory; a commit runs
`.git/hooks`. A repository cloned to read — a bug report's reproduction, a
dependency somebody linked — got the trust its owner's code gets.

Now a project is untrusted until you say otherwise, and says so in a strip at
the top of the window with the one button that changes it — and a *What is held
back* beside it, which opens two short lists: what waits, and what does not.
The strip can also be put away without trusting anything, in which case nothing
changes about the project and **File ▸ Trust This Project…** is where the
gesture lives. **Reading is
untouched**: the tree, the editor, syntax, folding, search, the git panes,
history, diffs, blame and the previews this app draws itself all work. What
waits is everything that executes by itself: running, debugging and building;
make, gradle and maven; devcontainers; language servers; and agents.

**The terminal is not one of them**, and the first cut had it wrong. A shell in
the project's directory is *your* shell with your configuration, and typing
`make` in it is you choosing to run that code exactly as you would in
Terminal.app — while refusing one costs the way you move between projects in a
terminal-first editor. What the shell must not do is run the project's own
files behind you, so an untrusted project's terminal gets `DIRENV_DISABLE`,
which is belt to direnv's own brace: it already refuses an `.envrc` nobody has
allowed.

**No environment variable the project asks for reaches anything.** A variable
is a command in every case that matters — `SOPS_AGE_KEY_CMD` is run by sops,
`GIT_SSH_COMMAND` and `GIT_EXTERNAL_DIFF` by git, and the loader's variables
choose what is loaded into a process that was never asked. They are dropped
rather than filtered against a list of dangerous names, because the dangerous
ones do not look dangerous.

**A commit declines the project's hooks and says so.** Not refused — reading a
repository and committing to it is work somebody may legitimately be doing, and
a mode that cannot commit is a mode people leave — but `--no-verify` is said on
the commit rather than done quietly.

**Trust is remembered by folder, and by where a clone came from.** The folder's
resolved path, in this app's own support directory beside the recents and never
inside the project — a repository that could grant itself trust would be the
whole hole. A parent folder can be trusted once (`~/dev`, rather than a hundred
checkouts), matched at a component boundary so `~/dev` is not `~/development`.
And a remote: a whole host for a server whose every repository is a
colleague's, or one owner on a host, since `github.com` is the world and an
organisation on it is a place. That last one is weaker on purpose and says so
where it is offered: a repository's remote is what its own `.git/config`
claims.

Trusting is a **choice of scope from a dropdown** — this project, the folder it
sits in, or where a clone says it came from — on the strip's button and in
File ▸ Project Trust alike, which is also where trust is taken back. A scope
that reaches past the project in front of you says what it covers before it is
granted. And a **public forge is never offered as a whole host**: `github.com`
is every repository anybody has ever pushed, so there the owner is the only
remote scope; an enterprise server is a place, and that is what the host scope
is for.

This is not a sandbox — it decides what starts, not what a trusted project's
build then does — and it is not a scanner: no heuristic reads a project and
decides it looks safe.

Driven against a project deliberately hostile to itself, each part leaving a
trace if it ran: a `Makefile` goal, a `launch.json` whose `env` sets
`SOPS_AGE_KEY_CMD` and `DYLD_INSERT_LIBRARIES`, a `pre-commit` hook and an
`.envrc`. Untrusted, every gesture refused with the same sentence and not one
trace; trusted, the goal ran and the strip was gone.
