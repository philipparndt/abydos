## Context

The save path from `2026-09-05-a-sops-file-decrypts-from-the-status-bar` has
one idea of "changed": `isDirty`. ⌘S on a decrypted tab does not even ask —
`save()` sends every decrypted buffer to `encryptAndSave`. And the paths that
*do* ask are told the wrong thing by undo: `TextDocument.travel(to:)` marks
the document dirty on the way back to a former state, so a value edited and
undone leaves the buffer "edited" while holding exactly the text `sops`
returned. Meanwhile `sops --encrypt` is randomised — same plaintext in, a
file sharing not one line with the last one out — so what the save produces
is a new version of the file, not a new version of the text.

The text to compare against exists already: `Sops.decrypt`'s stdout, which
`decrypt(_:)` puts into the buffer and then forgets. The pieces that must
agree are `decrypt`, `lockAgain`, the two encrypt entry points, the park and
restore round trip, and the quit gate's parked loop, which calls
`Sops.encryptSync` directly rather than through the editor's save path.

## Goals / Non-Goals

**Goals:**

- A decrypted buffer that still holds the decrypt's own plaintext saves
  without `sops` and without a write: the file keeps its bytes, the buffer
  locks back to the ciphertext from disk, clean, the chip reading
  *SOPS · encrypted* — the same end state an edited save reaches.
- Every route to an encrypt gets this for free: ⌘S, the chip, the close
  dialog's *Save*, the quit gate's *Encrypt and save*, open or parked.
- The comparison survives a project switch: the park carries the baseline and
  the restore puts it back.

**Non-Goals:**

- Not changing what "edited" means anywhere else. `isDirty` stays the tab's
  honest "somebody touched this" mark — the close dialog and the quit gate
  still ask about an edited-then-undone buffer; only the *write* is skipped.
- Not comparing digests, and not re-deriving the baseline anywhere: the
  decrypt's stdout is kept once, on the tab, and everything else reads it.
- Not touching the encrypt of a genuinely changed buffer, the changed-on-disk
  refusal, or any failure path.

## Decisions

### The baseline is the decrypt's stdout, kept on the tab as text

`Tab` gains `decryptedBaseline: String?`; `decrypt(_:)` sets it from
`result.stdout`, `lockAgain(_:)` clears it. A save asks one question —
`text(of: document) == tab.decryptedBaseline` — which is exact where
`isDirty` is a proxy that undo lies about.

*Ruled out:* judging by `isDirty` — it misses the edit-then-undo case, which
is the report's own example, and ⌘S ignores it today anyway.

*Ruled out:* keeping a SHA-256 of the plaintext instead of the text. The
digest saves a copy of a file that is kilobytes while the buffer's rope and
the undo tree already hold the whole of it, and it costs a hash on every
save and a third place that must agree on the algorithm. The driven report
hashes because a *log* must not hold a secret; memory is not a log.

### The skip sits inside the two encrypt entry points, after the disk guard

`encryptAndSave` and `encryptAndSaveSync` gain the same early branch: the
`hasChangedOnDisk` refusal stands first, then the comparison, then
`lockAgain(tab)` and `true`. Placing it after the disk guard is the whole
point of the ordering: a file that moved since the decrypt is not the file
this baseline came from, and the existing refusal — nothing written, a toast
— is the answer it already gets.

*Ruled out:* teaching `save()` to check `isDirty` before routing to the
encrypt — it would need the undo case anyway, and the close dialog and the
quit gate would each need their own copy of the decision. The entry points
are the one place every caller already converges on.

*Ruled out:* skipping the encrypt but leaving the buffer decrypted. A save
that ends with the plaintext still in the buffer is a lock that did not
happen, and the spec promises the ciphertext back; `lockAgain` is the same
route the chip takes on an unedited buffer, and it re-reads the file —
unchanged, so what it reads is the right ciphertext.

### The park carries the baseline; the quit gate's parked loop compares too

`DecryptedBuffer` gains `baseline: String?`, defaulting to nil, so the
existing call sites and tests compile untouched; `parkDecryptedTabs` passes
`tab.decryptedBaseline`, `restoreDecrypted` puts it back. The quit gate's
parked loop — which does not go through the editor's save path — compares
`parked.buffer.text` with `parked.buffer.baseline` before running `sops`, and
on a match discards the park: the ciphertext on disk already is this text's
version, and the buffer is dropped as *Discard* would drop it, because there
is nothing in it that the disk does not have.

*Ruled out:* re-deriving the baseline at restore from the parked text when
`isEdited` is false — it would lose exactly the edited-then-undone buffer the
skip exists for.

*Ruled out:* filtering baseline-equal buffers out of `DecryptedBuffers.edited()`
so the quit gate stops asking. `isEdited` means "somebody touched this" and
stays honest; the question is harmless and the answer is now cheap.

## Risks / Trade-offs

- [An external rewrite that keeps mtime and size could slip past
  `hasChangedOnDisk` and be kept] → the same exposure every save already
  rides: the guard is the one all this repository's saves trust, and the skip
  adds no new route past it. The refusal, when the guard does fire, is
  unchanged.
- [A second copy of the plaintext in memory per decrypted tab] → beside the
  rope and the undo tree that already hold it, and the park's own copy while
  the project is away; a secrets file is kilobytes. Cleared with the lock,
  like everything else about a decrypted buffer.
- [`EditorViewController.swift` sits at its raised ceiling] → the skip adds
  lines to a file at 5328; the finishing task checks the ceiling and raises
  it if the comments said their reasons — the debt the file records is
  reasons said aloud, one line wider.

## Migration Plan

None. The field defaults to nil, the park round trip carries it from the
first save of this change, and a parked buffer from before the change cannot
exist: parks live in memory for the app's life and are gone when it quits.

## Open Questions

None — the report names the behaviour and the spec says the rest.