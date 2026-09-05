## Context

The secrets lock is the model. `DotenvSecrets.conceals(fileNamed:)` decides by
name shape, `CodeView` draws covers over values at paint time, and
`EditorStatusView` shows a lock on the left that `EditorAreaController`
pushes state to — never asked for while drawing, since the bar redraws on
every caret move. `EditorViewController` computes `PreviewFacts` once at open
for facts that need a look inside the file; `Go3mfRecipe` is the precedent
for a bounded, cheap look.

A file leaves the editor through `TextDocument.save()` — `Data.write(.atomic)`
to its own URL — and comes back through `reloadFromDisk()`, which
`reloadExternallyChangedFiles()` runs on window focus, skipping dirty
documents. Auto-save is a `DispatchWorkItem` gated on a setting. There is no
read-only tab and no quit-time check; `confirmDiscard` asks Save/Discard/Cancel
when a dirty tab is closed, and a project switch closes every tab.

External tools are found by `Executables.locate`, which reads the login
shell's `PATH` once — `sops` and `age` live behind Homebrew or a version
manager, not on a GUI app's four directories — and run through
`ProcessPipes.drain`, which reads both pipes on threads of their own and
writes stdin from a third. `GitHubCLI` is the shape: `locate` with an
environment override for driven runs, `run` returning a `ProcessResult`.

`helmsec` (`~/dev/helmsec`) decides a file is SOPS's by a top-level `sops:`
line (`"sops":` in JSON), maps the extension to the format — yaml, yml, json,
env, ini — decrypts with the SOPS library and encrypts with `sops --encrypt
--input-type F --output-type F --output dst src`. `sops` 3.13 is on this
machine, with `age`.

## Goals / Non-Goals

**Goals:**

- A SOPS file is recognised at open and says so in the status bar.
- One press decrypts into the buffer; ⌘S encrypts the buffer back over the
  file. Both through `sops`, both through pipes.
- Plaintext never reaches a disk from this app, and never reaches a language
  server or a report.
- The decrypted values are covered as a `.env`'s are.
- A decrypted buffer, with its edits, survives a project switch in memory.
- Quitting with edited plaintext in hand asks, and can be cancelled.
- The classification, the command lines and the park are in AbydosKit and
  tested; the gesture is driven end to end against real `sops` and an `age`
  key made for the run.

**Non-Goals:**

- Encrypting a plaintext file for the first time. That needs a creation rule
  chosen and is `sops --encrypt` at a terminal; this change is for files that
  are already SOPS's.
- Keys. Whatever `sops` needs — an `age` key file, a PGP agent, a cloud CLI —
  it finds the way it does at a terminal, from the login shell's environment.
  A `gpg` that wants a pinentry gets whatever the machine's pinentry is; the
  app opens no terminal for it.
- Partial re-encryption. See the decision below.
- The `.dec` workflow. `helmsec` keeps writing `.dec` files for people who
  want them; the editor does not make one.

## Decisions

### A SOPS file is one that looks like one, decided once at open

`SopsFile.looksEncrypted(name:head:)`: the extension is one SOPS formats —
`yaml`, `yml`, `json`, `env`, `ini` — and the head of the file holds both
`ENC[` and a top-level `sops` key (`sops:` at column 0, or `"sops":`). Both,
because a YAML file with a `sops:` key of its own and no `ENC[` is not
encrypted, and a file with `ENC[` inside a string and no `sops` block is
somebody's test fixture. The look reads up to 256 KB — SOPS puts its block at
the *end* of a YAML file, so a head of 8 KB would miss it on any file with
more than a screen of values; a secrets file over 256 KB is not one, and is
left alone. Carried into the editor as a `PreviewFacts` field, computed once
where the go3mf fact is.

*Ruled out:* deciding by name, as `DotenvSecrets` does. There is no name
shape for a SOPS file — `secrets.yaml`, `values-prod.yaml`, `.env.enc` — and
`DotenvSecrets`'s argument against sniffing is about entropy heuristics on
arbitrary files; this is a literal string and a literal key, on files with
five extensions.

*Ruled out:* asking `sops` whether it is its file. A process per open of any
YAML file is the cost the go3mf look was written to avoid.

### The plaintext lives in the rope and nowhere else

Pressing the chip runs `sops --decrypt <file>` and reads stdout;
`CodeView.replaceAllText(with:)` puts it into the document as one edit, so
the caret, folds and scroll come back and ⌘Z would give the ciphertext back
— which is a way of re-locking a buffer, and harmless. The tab is marked
*decrypted*. From then on:

- **auto-save is off** for that document. `scheduleAutoSave` asks the
  document, and a decrypted document declines; a save is only ever ⌘S or
  the chip.
- **the session file gets the tab, not the text.** It never got text for any
  file; nothing new to keep out, and a test says so.
- **no language server hears it.** The document's `onTextChanged` does not
  forward to the server for a decrypted buffer, and the open/close
  announcements are not made. A YAML server would otherwise hold the
  plaintext in its own process and its own cache.
- **no report prints it.** The driver's report is the state, the line count
  and a digest of the text. A driven run that printed a decrypted value would
  be a run whose log is a secret.
- **no temp file, no `.dec`, no scratch.** The decrypt reads stdout; the
  encrypt writes stdin. Nothing in this change calls anything that takes a
  path for the plaintext.

*Ruled out:* `helmsec`'s `.dec` beside the original. It is what the tool does,
and it is the constraint given in so many words: not persisted anywhere.

*Ruled out:* `sops`'s own editor mode (`EDITOR=… sops file`). It writes the
plaintext to a temp file for the editor, which is the same thing one
directory over.

### Saving encrypts, through stdin, under the file's own name

⌘S on a decrypted buffer runs
`sops --encrypt --input-type F --output-type F --filename-override <path>
/dev/stdin` with the buffer on stdin, and writes stdout over the file with
the same atomic write `save()` uses. `--filename-override` is what lets the
project's `.sops.yaml` creation rules match a file that is arriving as stdin;
it is in `sops` since 3.9, and a `sops` without it is said in the toast. The
buffer stays decrypted and becomes clean; the file on disk is ciphertext,
re-read by nothing since the document's own disk state is recorded after the
write.

*Accepted, and said in the notes:* a whole-file encrypt takes a fresh data
key, so every value's ciphertext changes even where its plaintext did not,
and the git diff is every line. `helmsec enc` does the same today.
Re-encrypting only the changed values means holding SOPS's tree and data key,
which is the library and not the command line; open below.

### The decrypted values are the lock's, and arrive revealed

`CodeView.setConcealsSecrets` is told by the tab's decrypted state as well as
by the name: a decrypted SOPS buffer is a `.dec` that never touched disk. It
arrives *revealed*, with the lock open — asked for on 2026-09-05: "when
decrypting a file, it should also directly unmasked" — because pressing
*decrypt* is the explicit act the lock exists to demand, and a second press
to see what was just asked for would be the same question twice. The lock
shuts it at once and the idle limit shuts it in time, as for any covered
file. The setting that turns concealment off turns it off here too.

### A save puts the ciphertext back, so the file can be decrypted again

After `sops --encrypt` has written the file, the buffer is given the
ciphertext `sops` produced and the tab is an ordinary one again: chip
*encrypted*, auto-save allowed, the server told the file is open. Pressing
the chip decrypts again in place — asked for the same day: "it should be
possible to decrypt again without reopen". The chip on a decrypted buffer
with no edits does the same from the file on disk, which is also the way to
put a plaintext buffer away without saving anything.

*Ruled out:* the buffer staying decrypted after a save. It left no way back
but closing the tab, and a plaintext buffer that stays open after the person
has finished with it is a plaintext buffer on a shared screen.

### The chip is the lock's neighbour, pushed to like it

`EditorStatusView` gains a chip after the lock: *SOPS · encrypted* with a
closed-shield glyph, *SOPS · decrypted* with an open one, and *sops not
found* dimmed with the reason in its tooltip. Its state comes through
`refreshStatus(from:)` with the lock's; the view works nothing out while
drawing. Pressing it decrypts, or — when decrypted and dirty — encrypts and
saves; a decrypted, clean buffer's press does nothing and the tooltip says
⌘S encrypts.

*Ruled out:* a strip above the file, as the language-server banner is. A
strip is for a state somebody should resolve and then not see again; this is
a control they will press twice an hour, and the bar is where the lock they
press beside it already is.

*Ruled out:* a menu item only. Added too, under View beside *Reveal
Secrets*, so a keyboard reaches it; but the report was "using the status
bar", and that is where it lives.

### Parked in memory across a switch

`DecryptedBuffers`, keyed by standardised root and file path, holds the
text, the dirty flag and the caret of every decrypted tab the switch closes
— beside `ProjectSessions` and `DraftInbox`, which are the same idea for the
same reason. When the session reopens the file, the tab is built and, before
anything is drawn, given its parked buffer and its decrypted state back. A
parked buffer is not asked about by `confirmDiscard` on the way out: the
switch is not a close.

*Ruled out:* writing the buffer into the session file. It is the one place
the plaintext must not go.

*Ruled out:* refusing to switch while a decrypted buffer is dirty. The
report is that switching to work on something else is the ordinary case.

### Quitting asks, per file, and can be cancelled

`applicationShouldTerminate` asks the window for its edited decrypted
buffers — open tabs and parked ones — and shows one alert per file:
*Encrypt and save*, *Discard*, *Cancel*. *Encrypt and save* runs the save
path and stops with a toast if `sops` refuses, leaving the app open;
*Cancel* returns `.terminateCancel`. Unedited decrypted buffers need nothing:
the file on disk is the ciphertext.

This is the first quit-time gate in the app. Ordinary dirty tabs still quit
silently, which is out of this change's scope and noted in the proposal.

*Ruled out:* one alert for all files with a count. The names matter — one of
them may be the one to keep and another the one to drop.

### The proof is real `sops` with a key made for the run

The driven run makes an `age` key in the scratch project, a `.sops.yaml`
naming it, and a file encrypted with the real `sops`; `SOPS_AGE_KEY_FILE` in
the run's environment points at the key. Steps: `report` (state, lines,
digest), `decrypt`, `type:`, `encrypt`, and the switch flags already there
for the park. A run then decrypts the file at a terminal and compares
digests, so the report proves a round trip without printing a value.
`ABYDOS_SOPS` names a stand-in for a machine without `sops`, so the state
machine is driven where the tool is not.

## Risks / Trade-offs

- [The file changes on disk while a buffer is decrypted] → the reload on
  window focus skips a decrypted document as it skips a dirty one, and a
  save over a file whose disk state moved since the decrypt is refused with
  a toast naming it, as a stale save should be. Said in the spec.
- [`sops` asks for a passphrase or a pinentry] → it inherits the login
  environment, as it would at a terminal; a `gpg` with a graphical pinentry
  works, one that wants a tty fails, and the toast carries `sops`'s stderr.
- [A decrypt that takes seconds — a cloud KMS] → the chip shows the spinner
  `DrawnButton` has, the buffer stays as it was until the answer, and the
  tab is not blocked.
- [`--filename-override` missing] → `sops --version` is read once per run of
  the app and the chip says so before anything is typed into a buffer that
  could not be saved.
- [A crash with plaintext in memory] → nothing here writes a core, and the
  session store never held it; the loss is the edits, which is the loss a
  crash always is.
- [The digest in the report is of a secret] → SHA-256 of the whole text,
  which reveals nothing of it and is enough to say two texts are the same.

*Open:* re-encrypting only the changed values, so the diff of a one-line
edit is one line. It needs SOPS's tree and data key, which the library has
and the command line does not; `helmsec` is Go and links the library, so a
`helmsec` subcommand that takes plaintext on stdin and the original on disk
could do it — and would be the same design with a different command.

*Open:* whether *SOPS · encrypted* should also be offered from the tree's
row menu, so a file can be decrypted before it is opened.
