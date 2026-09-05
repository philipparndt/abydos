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
