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
