## Context

The editor already knows which files hold secrets: `DotenvSecrets` decides a
dotenv-shaped name or a `.dec`, the covers go on at open, and the lock in the
status bar says *Secrets hidden* or *Secrets shown*. The SOPS chip, since
yesterday, stands at the bar's left edge for a file `SopsFile.looksEncrypted`
recognises.

What is missing is the file's relationship with git. The navigator asks
`git status --ignored` per project and keeps an ignored set for its tints;
`BacklogCommands` asks `git check-ignore` for the handful of paths it writes.
Neither answer reaches the editor, and the editor is where somebody is looking
at the file whose values it is covering.

`sops` is already located (`Sops.locate`, honouring `ABYDOS_SOPS`) and already
run with `--filename-override` so that the project's `.sops.yaml` rules choose
the keys. What the app cannot say today is whether a *given* path has a rule
at all — and there is no YAML reader in this repository, on purpose.

## Goals / Non-Goals

**Goals:**

- Say, beside the lock, whether git can see the file whose values are covered,
  and distinguish "not ignored" from "already tracked", because the two have
  different next steps.
- Offer, on a plaintext file the project's `.sops.yaml` has a rule for, the
  one press that encrypts it, reusing the encrypt path the decrypted-buffer
  save already runs.
- Cost nothing on a file that is not concealing, and nothing per keystroke.

**Non-Goals:**

- Not guessing at secrets by reading contents: the question this answers is
  about files the editor *already* conceals, and a content sniffer would put a
  notice on somebody's fixture data.
- Not writing `.gitignore` — the navigator's *Add to .gitignore…* exists, asks
  first, and is where that gesture belongs.
- Not a modal, a toast or a badge in the tree: the notice belongs next to the
  control it is about, and a dialog at open is a dialog answered by reflex.
- Not adding a YAML dependency for `.sops.yaml`.
- Not rewriting history, and not offering to: a tracked file's values are in
  the history, and an editor that implied otherwise would be lying.

## Decisions

### Two git questions, asked once per file, off the main thread

`git check-ignore -q <path>` answers ignored (exit 0) or not (exit 1);
`git ls-files --error-unmatch <path>` answers tracked (exit 0) or not
(exit 1). Both cost the one path asked about — the measured `check-ignore` in
the navigator is 0.01 s for the paths it asks about — and both are asked once,
when a concealing file opens, on the same background path the SOPS look uses.
The pair is one type in the engine (`SecretExposure`), so the words and the
states are decided without a window and tested without one.

*Ruled out:* reading the navigator's ignored set — it is per project, built by
a sweep that may not have finished when a file opens from the palette, and a
notice that is right only after a sweep is a notice that is wrong at open.
*Ruled out:* asking on every save — the answer changes when `.gitignore`
changes or the file is added, and those are the two moments the editor already
hears about: an external reload and a git refresh. Asked again there, nowhere
else.

### The notice is text beside the lock, in the bar's own voice

*Not in .gitignore* for a file git could add, *Committed to git* for one it
already tracks, with the fuller sentence in the tooltip — the same drawn-chip
shape the lock and the SOPS chip already use, so it scales with the bar and
theme and cannot be a yellow system box. Nothing appears for a file git
ignores, for a project that is not a repository, or for a file that does not
conceal.

*Ruled out:* a colour on the lock — the lock says whether the values are
covered, which is a different fact, and one control saying two things is how
somebody reads neither.

### The offer is the SOPS chip's other side

`SopsRules` reads the project's `.sops.yaml` — a bounded line scan for
`path_regex:` values under `creation_rules:`, not a YAML parse — and answers
whether a path matches one. Where it does, and the file is not already
encrypted, the chip reads *SOPS · encrypt*; pressing it pipes the buffer
through `sops --encrypt` with `--filename-override` (the call the save path
already makes), writes the ciphertext over the file atomically, and leaves the
tab exactly as opening an encrypted file leaves it: chip *encrypted*, covers
on, nothing decrypted in memory.

*Ruled out:* showing the offer wherever a `.sops.yaml` exists and letting the
press fail — sops answers "no matching creation rules found" only after being
asked to encrypt, and a chip on every file in the repository is the noise the
request explicitly asked to avoid ("for a lot of files the user will not want
an encryption").
*Ruled out:* adding Yams to read `.sops.yaml` properly — the file is flat and
the one field needed is a list of regexes; the repository already wrote down,
for `pnpm-lock.yaml`, why a YAML library is not worth its keep here. A rule
the scan cannot read yields no offer, which is the safe direction: a missing
chip costs a menu press, a wrong one costs an unreadable file.

## Risks / Trade-offs

- [A `.sops.yaml` whose rules the line scan misreads] → the failure is a
  missing offer, never a wrong encrypt; and the press itself still goes
  through `sops`, which enforces its own rules and fails loudly.
- [Two `git` runs when a `.env` opens] → one path each, off the main thread,
  and only for a file that conceals. Said with the load beside it in the
  driven proof.
- [The notice on a file somebody deliberately commits — an example `.env`,
  a fixture] → it is a statement, not a dialog, and it goes when the file is
  ignored; the tooltip names the ignore gesture rather than nagging.
- [*Committed to git* arriving after the file is already in history] → it
  cannot undo that, and says so plainly rather than offering a fix that would
  leave the value in the history anyway.

## Open Questions

None: the request names the two halves, the SOPS work names the encrypt call,
and the navigator names the git questions.
