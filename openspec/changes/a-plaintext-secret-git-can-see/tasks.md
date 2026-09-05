## 1. What git can see, in the engine

- [x] 1.1 `Sources/AbydosKit/Git/SecretExposure.swift` — the two questions and
  the three answers (`ignored`, `notIgnored`, `tracked`) as one type, asked
  with `git check-ignore -q` and `git ls-files --error-unmatch` through
  `GitRepository.run`, one path each. The words the bar shows and the sentence
  the tooltip shows live here, so they are checkable without a window.
- [x] 1.2 `SecretExposureTests` — a fixture repository per claim: an ignored
  dotenv is `ignored`, an untracked and unignored one is `notIgnored`, a
  committed one is `tracked` even when a later `.gitignore` line matches it
  (git's own precedence, and the case that decides which sentence is right),
  and a folder that is not a repository answers nothing.

## 2. The creation rules

- [x] 2.1 `Sources/AbydosKit/Git/SopsRules.swift` — a bounded line scan of a
  project's `.sops.yaml` for the `path_regex` values under `creation_rules`,
  and `matches(_ path:)` against the project-relative path, with the comment
  saying why this is not a YAML parse and what the safe direction of failure
  is. No dependency added.
- [x] 2.2 `SopsRulesTests` — the shape `sops` documents (a list of rules, each
  with a `path_regex` and keys), a rule that matches and one that does not, a
  malformed rule yielding no match rather than a wrong one, and a missing
  `.sops.yaml` yielding none at all.

## 3. The bar

- [x] 3.1 `EditorViewController` asks `SecretExposure` once, off the main
  thread, when a concealing file opens, and again on an external reload and a
  git refresh; the answer is pushed to `EditorStatusView` the way the lock and
  the SOPS chip are pushed.
- [x] 3.2 `EditorStatusView` draws the notice beside the lock — *Not in
  .gitignore*, *Committed to git*, nothing when ignored — with the consequence
  in a tooltip, hit-testing and hover as the other chips have them, and the
  lock's own words unchanged.
- [x] 3.3 The SOPS chip's plaintext state: *SOPS · encrypt* where
  `SopsRules.matches` says so and the file is not already encrypted, and the
  press that encrypts through the existing `Sops.encrypt` and
  `TextDocument.replaceOnDisk`, leaving the tab as an encrypted file opens.

## 4. Proving it

- [x] 4.1 The driver: the exposure and the offer in the reports the SOPS and
  secrets steps already print, so a driven run can say the state without
  printing a value.
- [x] 4.2 Driven on 2026-09-05 over a scratch repository with real `sops`
  3.13.3 and an `age` key made for the run, a debug build under the throwaway
  id `de.rnd7.abydos.exposure`:
  - *The three answers:* `.env.ignored` (a `.gitignore` line) reports
    `git=fine`; `.env`, untracked and unignored, `git=not-ignored`;
    `.env.committed`, committed before the run, `git=tracked` — and
    `plain.yaml`, which conceals nothing, `git=fine` with git never asked.
  - *The notice's action:* `.env` reporting `not-ignored`, the `ignore` step
    (the menu item's own door), and the next report `fine` — with `.env`
    written into `.gitignore` beside the line that was already there.
  - *The offer:* `secrets/dev.yaml`, matched by the project's creation rule,
    reports `state=offer`; pressed, the file on disk becomes SOPS ciphertext
    (2 lines of `ENC[…]` and the `sops:` block, 18 lines from 3), the buffer
    shows it, the chip reads `encrypted`, and `sops --decrypt` at the terminal
    gives back `password: hunter2` and `token: abc123` — the text that was
    there.
  - *Photographed:* the footer on the unignored `.env` reading *Secrets
    hidden* and then *Not in .gitignore*, with the value covered in the
    editor behind it.

## 5. The amendment: the notice is a control, and it stays put

*Asked for while this was being applied: "moving the mouse over the new
secrets label makes it move", and "maybe the label should have a active menu
with the option to add the file to gitignore".*

- [x] 5.0a **The label walked.** Its left edge came from `leftChipsExtent()`,
  which this change had just taught to count `exposureRect` — so every redraw
  put it one gap further along than the last, and a hover is a redraw. The
  extent the *server* chip asks for still counts all three, because that is
  the question it is asking; the notice measures itself from
  `chipsBeforeExposure()`, the two chips it stands after, and the comment says
  which mistake that split is for.
- [x] 5.0b The notice is pressable: a pointing-hand cursor, and a menu
  offering *Add this file to .gitignore*, which writes the file's path from
  the repository root through `GitIgnore.add`, says what it wrote, posts the
  repository-changed notice and asks git again — so the notice goes by itself.
  For a tracked file the menu says git already tracks it and offers no ignore
  line, since ignoring it now would not take its values out of the history.
  The tree's own dialog, where a pattern can be edited, is untouched: a
  status-bar press is for the file in front of somebody.
- [x] 5.0c The delta spec says both — the notice keeping its place under the
  pointer, and the menu — rather than leaving them as behaviour nobody wrote
  down.

## 5. Finishing

- [x] 5.1 `Scripts/file-size-allowed.txt` raised for
  `EditorViewController.swift` 5581 → 5849: the tab's two new facts and the
  ask behind them, the notice with its tooltip, its menu and its own extent,
  the chip's offer state and the encrypt-in-place path, and the driver's three
  steps — reasons said aloud, the debt the file records.
  `docs/release-notes-0.14.0.md` has the section, the menu and the offer
  included.
- [x] 5.2 Green by their exit codes: `make test` 4104 tests in 522 suites,
  exit 0 with the suite's two standing known issues, load 71.6 over 10 cores;
  `make warnings` exit 0 — after one it caught, a `_ =` in front of a
  Void-returning `save()`, which is the verb this change reused rather than
  the one it thought it had. The four sops and exposure suites re-run green
  after that fix.
