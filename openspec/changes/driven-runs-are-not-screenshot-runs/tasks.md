## 1. Establish both reproductions

- [ ] 1.1 Reproduce the project switch deliberately: a scratch project, a preference
      domain with `followsTerminalProject` true, and a terminal whose working
      directory has been deleted underneath it. It went five for five on this machine.
- [ ] 1.2 Record what that run looks like from outside — `--print-text` printing
      `no editor`, `--close-window` reporting a window showing zshutil — so the
      after-state is a comparison rather than an assertion of faith.
- [ ] 1.3 Reproduce the blank sidebar: `--sidebar-shot` with no `--screenshot`, and
      keep the picture. It exits zero, which is why it was believed once already.

## 2. Read the gate before moving anything

- [ ] 2.1 List every site asking `isScreenshotRun` — around twenty, across
      `AppDelegate`, `MainWindowController` and `ClaudeWatch` — with what each does.
- [ ] 2.2 For each, record which question it means: "is this run producing a picture"
      or "was `--screenshot` given". This list is the work; the arithmetic is a line.
- [ ] 2.3 Confirm the follow guard at `MainWindowController.swift:2039` is in the
      first group. Its comment already argues for the broader rule — "a capture is of
      a named project" — and records that 0509 found the rule broader than photography
      once before, without the test being widened with it.

## 3. Split the property

- [ ] 3.1 Introduce the two properties, each named for the question it answers, and
      move every site onto the one it means.
- [ ] 3.2 The follow guard asks whether the run is driven. Update its comment to say
      what the narrow test cost, rather than leaving it reading as if it had always
      been correct.
- [ ] 3.3 Suppress the follow at the point the pane's report is acted on, rather than
      by filtering which preferences a driven run copies.
- [ ] 3.4 Grep for every other path into `switchProject(to:followingTerminal:)` and
      say here whether any is reachable in a driven run.
- [ ] 3.5 Somebody working in a window still follows their terminal — checked, not
      assumed, because that is the feature this must not break.

## 4. The project is decided once

- [ ] 4.1 Move the driven-run decision ahead of the branches written for an ordinary
      launch, so "it opens what it was given, or it fails" is readable in one place.
- [ ] 4.2 A driven run with an unopenable `--open` writes the path to stderr and exits
      non-zero, opening nothing.
- [ ] 4.3 A driven run with no `--open` opens nothing — 0522's guard, kept, now at the
      top rather than fourth.
- [ ] 4.4 One line naming the resolved project root, standardised. Decide stdout or
      stderr, and check no driver verb's parser is broken by it.

## 5. The capture flags

- [ ] 5.1 `--sidebar-shot <path>` with no `--screenshot` writes the sidebar as it is
      on screen. Confirmed by looking at the picture, not by the exit code.
- [ ] 5.2 Any capture that genuinely cannot be produced says so on stderr, exits
      non-zero, and writes nothing.
- [ ] 5.3 Sweep the driver flag table for any other capture-ish flag that does not set
      `screenshotPath`, and name what was found here — including the finding being
      nothing.

## 6. The paths that made this hard to see

- [ ] 6.1 A scratch copy under `/private/tmp` opened as `/tmp/...` shows that copy —
      the symlink case, tested specifically.
- [ ] 6.2 A test for the refusal case, since that is the one nobody would notice.

## 7. Finish

- [ ] 7.1 `make test` and `make warnings` both clean.
- [ ] 7.2 Write down what was ruled out on the way, including that the
      recent-projects list has nothing to do with 0534, and that widening
      `isScreenshotRun` in place was considered and refused as leaving the same trap
      for the next capture flag.
- [ ] 7.3 `.abydos/backlog/spec/terminal.md` and `screenshots.md` say what the project
      now does, then re-run `openspec/extract-from-backlog.py` so `openspec/specs/`
      matches. Add any new requirement's normative line to `openspec/normative.json` —
      the extractor reports it by name if it is missing.
- [ ] 7.4 Retire the workaround from 0533 and 0534 (`make build BUNDLE_ID=…` plus a
      pre-seeded defaults domain) or say why it is still needed for other reasons.
- [ ] 7.5 Close backlog 0534 and 0535 together, noting that they were one defect.
