## Why

A SOPS-encrypted file — `secrets-dev.yaml` with every value an
`ENC[AES256_GCM,…]` string and a `sops:` block at the end — opens in the
editor as exactly that: ciphertext, readable by nobody, editable by nobody.
Working on one today means leaving the app: `helmsec dec` writes a plaintext
`.dec` beside it, the `.dec` is edited, `helmsec enc` writes it back, and the
plaintext sits on disk in between, kept out of the repository only by a
`.gitignore` line. The app already knows how secret such a file is —
`DotenvSecrets` names `*.dec` as "the most secret-laden file a screen can
show" and covers its values — and offers nothing for the encrypted original
beside it.

Asked for on 2026-09-04: "when working with sops encrypted files, it would be
nice to be able to decrypt them using the status bar of the editor. We already
support masking secrets from a UI perspective this is similar." With three
constraints given in the same conversation: the decrypted contents remain
secure and are not persisted to any temp folder or anything like it; edits to
a decrypted file survive a project switch while the app is open; and quitting
with such edits in hand asks whether to persist them, with cancel.

`~/dev/helmsec` is the reference for how the tool works: a file is SOPS's
when a top-level `sops:` key is present (`"sops":` in JSON), the format
follows the extension — yaml, json, dotenv, ini — decryption goes through
SOPS's library, and encryption shells out to `sops --encrypt`. What it does
with the plaintext, writing a `.dec`, is the one part this change does not
copy.

There is no originating `.abydos/backlog` item.

## What Changes

- **A SOPS file says so in the status bar, and decrypts from there.** A file
  whose extension is one SOPS handles and whose contents carry `ENC[` values
  and a top-level `sops` key gets a chip beside the secrets lock, *SOPS ·
  encrypted*. Pressing it runs `sops --decrypt` on the file and puts what
  comes back on stdout into the editor's buffer. The chip then reads *SOPS ·
  decrypted*, and the buffer is edited as any file is.
- **Nothing decrypted touches a disk.** No `.dec`, no temp file, no scratch:
  the plaintext exists in the document's rope and its undo stack and nowhere
  else. Auto-save is off for a decrypted buffer. The session file records the
  tab and its caret as it does for any file and never its text. No language
  server is told what the buffer holds. The driven run's reports say what
  state a buffer is in and never what is in it.
- **Saving a decrypted buffer encrypts it.** ⌘S pipes the buffer into
  `sops --encrypt` on stdin, with the original file's name given so the
  project's `.sops.yaml` rules pick the same keys, and writes the ciphertext
  back over the original. The buffer stays decrypted afterwards, clean. The
  chip offers the same as *Encrypt & save*.
- **The decrypted values are covered.** A decrypted buffer gets the secrets
  covers whatever the file is called, and the lock beside the chip works as it
  does for a `.env`. The two controls sit together on the left of the bar.
- **Edits survive a project switch.** A decrypted buffer, edited or not, is
  parked in memory by root and file when the window leaves the project, and
  put back into its tab when the session reopens the file. It is never
  written to the session on disk.
- **Quitting asks.** With an edited decrypted buffer anywhere in the window —
  open or parked — quitting shows *Encrypt and save*, *Discard*, *Cancel*, per
  file, and *Cancel* stops the quit. An unedited decrypted buffer is dropped
  without a word, since the ciphertext is on disk. This is the app's first
  quit-time gate: today it quits without asking about any unsaved tab.
- **A file that is not a SOPS file is untouched.** No chip, no reading of
  content beyond the bounded look that classifies it, nothing per keystroke.

## Capabilities

### New Capabilities

- `sops-files`: how a SOPS-encrypted file is recognised, what the status bar
  offers, where the plaintext lives and does not, how a save encrypts, what
  survives a switch, and what quitting asks.

### Modified Capabilities

- `secret-concealment`: "Dotenv values are concealed by default" gains the
  decrypted SOPS buffer as a case decided by what the buffer is, not by the
  file's name; "A value is shown only by an explicit action" names the chip
  as the lock's neighbour on the left of the bar.

## Impact

- **AbydosKit**: `SopsFile` — the classification (extension, `ENC[`, the
  `sops` key) from a bounded read, the format for a name, the two command
  lines, and the parsing of `sops`'s answer — tested without a window and
  without `sops`. `Sops` runs the command found by `Executables.locate`,
  through `ProcessPipes`, with stdin for the plaintext and an environment
  override for a driven run. `DecryptedBuffers` — the in-memory park, keyed
  by root and file, beside `ProjectSessions` and `DraftInbox`.
- **AbydosApp**: a chip in `EditorStatusView` beside the lock, pushed to as
  the lock is; a decrypted state on the tab that turns off auto-save, keeps
  the language server out, and sends ⌘S to the encrypt path; `PreviewFacts`
  carries the classification to the editor; a quit gate in `AppDelegate`.
- **Driver**: `--sops <steps>` — `decrypt`, `encrypt`, `type:`, `report`,
  `switch`-friendly — with a report that names the state and the line count
  and a digest, never the text; `ABYDOS_SOPS` to name the command, as
  `ABYDOS_GH` does for `gh`.
- **Cost**: one bounded read at open for files with a SOPS extension; one
  process per decrypt and per save; a set lookup at auto-save time; nothing
  per keystroke.
