## Why

**The editor covers a `.env`'s values on the screen and says nothing about the
far worse exposure: that git can see the file at all.** Concealment is for the
shared screen — the call somebody joined with the file already open — and it
is drawn from the moment the file opens. Whether that same file is about to
be committed, pushed and read by everybody who clones the repository is a fact
the editor already has the means to know (the navigator asks
`git status --ignored` for every project it opens, and `BacklogCommands` asks
`git check-ignore` for the files it writes) and never says.

Asked for on 2026-09-05, as an extension of the secrets area: "a natural
extension of the 'secrets' area in the editor could be to show that
unencrypted file containing secrets is not gitignored", and with it "to
initially sops encrypt a matching file (this is not a warning, just a
possibility. For a lot of files the user will not want an encryption)".

No originating backlog item: asked for directly, the day after the SOPS work
landed as `2026-09-05-a-sops-file-decrypts-from-the-status-bar`.

## What Changes

- **A concealing file that git is not ignoring says so, once, where the lock
  already is.** A file whose values the editor covers — dotenv-shaped, or a
  `.dec` — that `git check-ignore` does not claim, in a project that is a git
  repository, shows a notice beside the secrets lock: this file is not
  ignored, and committing it commits the values under those covers. It is a
  statement of fact next to the control it is about, not a modal and not a
  toast: a warning that interrupts is a warning that gets dismissed by reflex.
- **A file git already tracks is said differently.** "Not ignored" is a
  mistake somebody can still fix by adding a line to `.gitignore`; *already
  committed* is one they cannot, because the value is in the history whatever
  the working tree does now. The notice says which of the two it is, since the
  next step is not the same.
- **A plaintext file the project's `.sops.yaml` has a rule for can be
  encrypted from the same place — an offer, not a warning.** Where a creation
  rule in the project's `.sops.yaml` matches the file's path, the SOPS chip
  appears on the plaintext file reading *SOPS · encrypt*, and pressing it runs
  the same `sops --encrypt` the decrypted-buffer save already runs, writes the
  ciphertext over the file, and leaves the tab in the state a SOPS file opens
  in. With no `.sops.yaml`, or no rule that matches, there is no chip and
  nothing is said: most files are not meant to be encrypted, and an editor
  that asked about each of them would be answered by rote.
- **Not proposed:** writing to `.gitignore` on the file's behalf (the
  navigator's *Add to .gitignore…* is a gesture that already exists and asks),
  scanning file *contents* to guess at secrets, or saying anything about a
  file the editor does not already conceal.

## Capabilities

### New Capabilities

- `secrets-git-can-see`: which concealing files are asked about, what the
  editor says when git is not ignoring one and when git already tracks it,
  where it is said, and when the answer is asked for again.

### Modified Capabilities

- `sops-files`: *A SOPS file is recognised when it opens and says so in the
  status bar* covers a file that is already encrypted. It gains the other
  side: a plaintext file with a matching creation rule in the project's
  `.sops.yaml`, whose chip offers to encrypt it, and what that press does —
  the same `sops --encrypt` over the file, with nothing written anywhere else.

## Impact

- `Sources/AbydosKit/Git/GitRepository.swift` — one bounded
  `git check-ignore` per concealing file opened, and the tracked answer from
  `git ls-files --error-unmatch`; both cost the one path they are asked
  about, off the main thread as the navigator's ignored sweep already is.
- `Sources/AbydosKit/Git/SopsRules.swift` — new: a bounded line scan of a
  project's `.sops.yaml` for the `path_regex` of its creation rules, and the
  answer to whether a path matches one, so the offer is decided without
  running `sops` on a file nobody asked to encrypt. **No YAML reader is
  added** — there is none in this repository, and the `pnpm-lock.yaml` item
  that wanted one wrote down why it did not add Yams either; a rule the scan
  cannot read is a file with no offer, never a wrong offer.
- `Sources/AbydosApp/Editor/EditorViewController.swift` — the notice beside
  the lock in `EditorStatusView`, the chip's new plaintext state, and the
  press that encrypts a file that was never decrypted.
- No new dependency: `check-ignore`, `ls-files` and `sops` are all already
  run from here, and `.sops.yaml` is read as YAML the project already parses.
