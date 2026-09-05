## Why

**`sops --encrypt` is randomised end to end — a fresh data key, fresh nonces, a
fresh MAC — so encrypting the same plaintext twice gives two files that share
not one line.** The save path that landed yesterday sends every save of a
decrypted buffer through it: ⌘S encrypts unconditionally, and the chip, the
close dialog and the quit gate all trust `isDirty`, which an undo leaves set
(`TextDocument.travel` marks the document dirty on the way *back* too). So a
file opened, decrypted, read and not changed is a file that changes: press ⌘S
out of habit, or edit a value and undo the edit, then save — and the file on
disk is a new version of itself, git showing every `ENC` value rewritten,
while `sops -d` gives back exactly the text it gave before. Reported on
2026-09-05: "when opening a sops encrypted file and decrypt the file content
is automatically changed later on. It should be possible to decrypt, read the
file and then even press the encrypt button. As long as the file is not
changed it shall remain the same version (encryption can be skipped)."

No originating backlog item: asked for directly on 2026-09-05, the day after
the sops work landed as
`2026-09-05-a-sops-file-decrypts-from-the-status-bar`.

## What Changes

- **The plaintext exactly as `sops` gave it back is kept on the tab** when a
  decrypt succeeds, beside the buffer that holds it, and goes wherever the
  buffer goes — a project switch's park and restore, in memory, as it already
  does — and nowhere else.
- **An encrypt whose text is still that plaintext is skipped.** Every save
  path — ⌘S, the chip on an edited buffer, the close dialog's *Save*, the quit
  gate's *Encrypt and save*, for a buffer open or parked — first asks whether
  the buffer still holds what the decrypt returned. When it does, the
  ciphertext on disk already *is* this text's version: no `sops --encrypt`,
  no write, the file keeps its bytes, and the buffer is locked back to that
  ciphertext exactly as a save locks it.
- **Everything else about saving stands.** An edited buffer encrypts and
  writes as it does today; a file that moved on disk is still refused; a
  failed encrypt still changes nothing and says why.

## Capabilities

### New Capabilities

<!-- None: saving a decrypted buffer is already specified. This is about what
an unchanged one costs the file. -->

### Modified Capabilities

- `sops-files`: *Saving a decrypted buffer encrypts it over the file* gains
  the one case it was missing — a buffer still holding the decrypt's own
  plaintext SHALL NOT be sent through `sops` at all, and the file SHALL keep
  the bytes it has. The quit gate's *Encrypt and save* runs this same save
  path, so the parked loop follows it too.

## Impact

- `Sources/AbydosKit/Project/DecryptedBuffers.swift` — the parked buffer
  carries the decrypt's plaintext beside its own text, an optional field
  with a default, so the park and restore round trip keeps the skip working.
- `Sources/AbydosApp/Editor/EditorViewController.swift` — the tab remembers
  the baseline; `decrypt` sets it, `lockAgain` clears it, `encryptAndSave`
  and `encryptAndSaveSync` return the lock instead of a write when the buffer
  equals it.
- `Sources/AbydosApp/MainWindowController+Layout.swift` — the quit gate's
  parked loop, which does not go through the editor's save path, applies the
  same comparison before it runs `sops`.
- No new cost: one string per decrypted tab, in memory only, beside the
  buffer that already holds the same text; one comparison per save.