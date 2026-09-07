## Why

**A PGP key with a passphrase cannot be used from the chip.** Pressing *SOPS
· encrypted* runs `sops --decrypt`, sops hands the data key to `gpg`, and
`gpg` needs the key's passphrase. In a terminal the agent asks through a
pinentry on the tty; a Dock-launched app has no tty, and unless a graphical
pinentry happens to be installed and configured the ask fails inside gpg with
words about a pinentry or an ioctl, and the toast says *could not decrypt*
with them. The same `sops -d` in the terminal pane beside it works, after
the passphrase is typed. Someone with a passphrase-protected key — which is
what a PGP key is supposed to be — cannot use the chip at all.

Asked for on 2026-09-07: "it should be possible to enter a passphrase when
decrypting sops. There shall be a password input box embedded in the status
line where we select decrypt".

No originating backlog item: asked for directly.

## What Changes

- **A passphrase field in the status bar, at the chip.** Pressing the chip
  tries the decrypt as it does today, so a cached passphrase, an agent with
  a working pinentry, and an age key all keep working without a question.
  When gpg fails for want of a passphrase, the chip's place in the status
  bar becomes a secure field — *Passphrase for 0xDEADBEEF…* — with what gpg
  said beside it; Return retries with the passphrase, Escape puts the chip
  back. Nothing modal, nothing floating.
- **The passphrase reaches gpg and nothing else.** sops honours
  `SOPS_GPG_EXEC`; the app points it at a small wrapper that runs gpg with
  `--pinentry-mode loopback --passphrase-fd` and reads the passphrase from a
  pipe the app holds open across sops. It is never an argument, never an
  environment variable, never a file, and never in the toast.
- **Kept for the sitting.** A passphrase that worked is kept in memory,
  keyed to the key it unlocked, until the app quits, so locking and
  decrypting again does not ask again. It is written nowhere.
- **A wrong passphrase says so** in the field's own words and keeps the
  field, rather than a toast and a chip.
- **Not proposed:** passphrase-protected age identities, which sops itself
  does not read; presetting the passphrase into gpg-agent, which needs an
  agent option most people have not set; asking before the first attempt,
  which would ask people whose agent already knows.

## Capabilities

### New Capabilities

<!-- None. -->

### Modified Capabilities

- `sops-files`: *Pressing the chip decrypts into the buffer, and nowhere
  else* gains the passphrase: when it is asked for, where it is typed, how it
  travels, what is kept and what is never written.

## Impact

- `Sources/AbydosKit/Git/Sops.swift` — `decrypt(_:passphrase:)`, the pipe,
  the wrapper's path and contents, and `needsPassphrase(_ stderr:)`, which
  reads gpg's words for the shape of the failure.
- `Sources/AbydosKit/Git/Passphrases.swift` — the in-memory keep, keyed by
  the key's fingerprint or the file's project, never persisted.
- `Sources/AbydosApp/Editor/EditorViewController.swift` — the decrypt path
  asks the bar for a passphrase on that failure and retries; the status view
  hosts the field where the chip was.
- `Sources/AbydosApp/LaunchOptions.swift` and the sops driver — a
  `passphrase:<text>` step, driven against a fake gpg that reports what it
  read on the fd, and a real key when gpg and sops are on the machine.
- Tests: the fd plumbing with a fake sops and a fake gpg; the failure
  detection from recorded gpg messages; the keep.
