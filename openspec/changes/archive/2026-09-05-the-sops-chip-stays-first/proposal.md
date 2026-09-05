## Why

**The chip you press to decrypt slides away the moment you press it.** A SOPS
file encrypted shows its chip at the left edge of the status bar, because
nothing else is there; the decrypt reveals the file's values, the secrets lock
comes up at the edge, and the chip — the very thing under the cursor — jumps to
the right of it. Reported on 2026-09-05 with two screenshots: *SOPS · encrypted*
standing alone, and *SOPS · decrypted* arriving second behind *Secrets shown*.

The order was drawn that way for a reason that has not survived contact: the
chip after the lock, "the file's encryption beside the file's covers". What it
gives in reading order it costs in aim — the chip is a button, and a button that
moves between its two states is a button nobody learns to reach for. The lock
can follow the chip as easily as lead it: both are the file's facts, and neither
changes width when the other is shown.

No originating backlog item: asked for directly on 2026-09-05, the day after the
sops work landed as `2026-09-05-a-sops-file-decrypts-from-the-status-bar`.

## What Changes

- **The SOPS chip is always the first item at the left edge of the editor's
  status bar**, at the same place in every state — encrypted, decrypted,
  edited, dimmed for a missing `sops` — whether the lock is shown or not.
- **The lock follows the chip** when both are shown: chip at the edge, lock to
  its right, one gap between them, neither moving the other.
- **Not proposed: changing what either control does.** Pressing the chip still
  decrypts, encrypts and saves, or puts the ciphertext back; pressing the lock
  still shows and hides the file's secrets; pressing one still changes nothing
  about the other.

## Capabilities

### New Capabilities

<!-- None: both controls are already specified. This is about where they stand. -->

### Modified Capabilities

- `sops-files`: *A SOPS file is recognised when it opens and says so in the
  status bar* says the chip sits beside the secrets lock. It moves to the front:
  the chip is the bar's first item, at the left edge in every state, and the lock
  follows it when both are shown.
- `secret-concealment`: *A value is shown only by an explicit action* pins the
  lock to the left, the chip beside it, so that "pressing one SHALL NOT change
  the other" — a sentence about state that its position clause keeps putting to
  the test. The lock keeps its place *relative to the chip*; the chip keeps its
  place on the screen.

## Impact

- `Sources/AbydosApp/Editor/EditorViewController.swift` — `EditorStatusView`'s
  `draw` order and two origins: `drawSops` at the edge always, `drawLock` after
  `sopsRect` when both are shown. Hit-testing, hover and tooltips already work
  off the rectangles and follow them unchanged.
- No change to `EditorAreaController`'s pushing of state, to AbydosKit, or to
  any spec scenario about decrypting, encrypting or concealing — only to where
  the two chips stand.
