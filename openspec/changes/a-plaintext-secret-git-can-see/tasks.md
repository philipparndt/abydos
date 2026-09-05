## 1. What git can see, in the engine

- [ ] 1.1 `Sources/AbydosKit/Git/SecretExposure.swift` — the two questions and
  the three answers (`ignored`, `notIgnored`, `tracked`) as one type, asked
  with `git check-ignore -q` and `git ls-files --error-unmatch` through
  `GitRepository.run`, one path each. The words the bar shows and the sentence
  the tooltip shows live here, so they are checkable without a window.
- [ ] 1.2 `SecretExposureTests` — a fixture repository per claim: an ignored
  dotenv is `ignored`, an untracked and unignored one is `notIgnored`, a
  committed one is `tracked` even when a later `.gitignore` line matches it
  (git's own precedence, and the case that decides which sentence is right),
  and a folder that is not a repository answers nothing.

## 2. The creation rules

- [ ] 2.1 `Sources/AbydosKit/Git/SopsRules.swift` — a bounded line scan of a
  project's `.sops.yaml` for the `path_regex` values under `creation_rules`,
  and `matches(_ path:)` against the project-relative path, with the comment
  saying why this is not a YAML parse and what the safe direction of failure
  is. No dependency added.
- [ ] 2.2 `SopsRulesTests` — the shape `sops` documents (a list of rules, each
  with a `path_regex` and keys), a rule that matches and one that does not, a
  malformed rule yielding no match rather than a wrong one, and a missing
  `.sops.yaml` yielding none at all.

## 3. The bar

- [ ] 3.1 `EditorViewController` asks `SecretExposure` once, off the main
  thread, when a concealing file opens, and again on an external reload and a
  git refresh; the answer is pushed to `EditorStatusView` the way the lock and
  the SOPS chip are pushed.
- [ ] 3.2 `EditorStatusView` draws the notice beside the lock — *Not in
  .gitignore*, *Committed to git*, nothing when ignored — with the consequence
  in a tooltip, hit-testing and hover as the other chips have them, and the
  lock's own words unchanged.
- [ ] 3.3 The SOPS chip's plaintext state: *SOPS · encrypt* where
  `SopsRules.matches` says so and the file is not already encrypted, and the
  press that encrypts through the existing `Sops.encrypt` and
  `TextDocument.replaceOnDisk`, leaving the tab as an encrypted file opens.

## 4. Proving it

- [ ] 4.1 The driver: the exposure and the offer in the reports the SOPS and
  secrets steps already print, so a driven run can say the state without
  printing a value.
- [ ] 4.2 A driven run over a scratch repository: an ignored `.env` (nothing
  said), an unignored one (*Not in .gitignore*), a committed one (*Committed
  to git*), a `.gitignore` line added and the notice gone; and, with a
  `.sops.yaml` and an `age` key made for the run, a matching plaintext file
  offered *SOPS · encrypt*, pressed, and `sops --decrypt` at the terminal
  giving back what was there. The two `git` runs timed with the load beside
  them.

## 5. Finishing

- [ ] 5.1 `Scripts/file-size-allowed.txt` raised for what grew, with the
  reasons said aloud, and `docs/release-notes-0.14.0.md` given the section.
- [ ] 5.2 `make test` and `make warnings`, both clean by their exit codes.
