## 1. Establish both reproductions

- [x] 1.1 Reproduce the project switch deliberately: a scratch project, a preference
      domain with `followsTerminalProject` true, and a terminal whose working
      directory has been deleted underneath it. It went five for five on this machine.
- [x] 1.2 Record what that run looks like from outside — `--print-text` printing
      `no editor`, `--close-window` reporting a window showing zshutil — so the
      after-state is a comparison rather than an assertion of faith.
- [x] 1.3 Reproduce the blank sidebar: `--sidebar-shot` with no `--screenshot`, and
      keep the picture. It exits zero, which is why it was believed once already.

## 2. Read the gate before moving anything

- [x] 2.1 List every site asking `isScreenshotRun` — around twenty, across
      `AppDelegate`, `MainWindowController` and `ClaudeWatch` — with what each does.
- [x] 2.2 For each, record which question it means: "is this run producing a picture"
      or "was `--screenshot` given". This list is the work; the arithmetic is a line.
- [x] 2.3 Confirm the follow guard at `MainWindowController.swift:2039` is in the
      first group. Its comment already argues for the broader rule — "a capture is of
      a named project" — and records that 0509 found the rule broader than photography
      once before, without the test being widened with it.

## 3. Split the property

- [x] 3.1 Introduce the two properties, each named for the question it answers, and
      move every site onto the one it means.
- [x] 3.2 The follow guard asks whether the run is driven. Update its comment to say
      what the narrow test cost, rather than leaving it reading as if it had always
      been correct.
- [x] 3.3 Suppress the follow at the point the pane's report is acted on, rather than
      by filtering which preferences a driven run copies.
- [x] 3.4 Grep for every other path into `switchProject(to:followingTerminal:)` and
      say here whether any is reachable in a driven run.
- [x] 3.5 Somebody working in a window still follows their terminal — checked, not
      assumed, because that is the feature this must not break.

## 4. The project is decided once

- [x] 4.1 Move the driven-run decision ahead of the branches written for an ordinary
      launch, so "it opens what it was given, or it fails" is readable in one place.
- [x] 4.2 A driven run with an unopenable `--open` writes the path to stderr and exits
      non-zero, opening nothing.
- [x] 4.3 A driven run with no `--open` opens nothing — 0522's guard, kept, now at the
      top rather than fourth.
- [x] 4.4 One line naming the resolved project root, standardised. Decide stdout or
      stderr, and check no driver verb's parser is broken by it.

## 5. The capture flags

- [x] 5.1 `--sidebar-shot <path>` with no `--screenshot` writes the sidebar as it is
      on screen. Confirmed by looking at the picture, not by the exit code.
- [x] 5.2 Any capture that genuinely cannot be produced says so on stderr, exits
      non-zero, and writes nothing.
- [x] 5.3 Sweep the driver flag table for any other capture-ish flag that does not set
      `screenshotPath`, and name what was found here — including the finding being
      nothing.

## 6. The paths that made this hard to see

- [x] 6.1 A scratch copy under `/private/tmp` opened as `/tmp/...` shows that copy —
      the symlink case, tested specifically.
- [x] 6.2 A test for the refusal case, since that is the one nobody would notice.

## 7. Finish

- [x] 7.1 `make test` and `make warnings` both clean.
- [x] 7.2 Write down what was ruled out on the way, including that the
      recent-projects list has nothing to do with 0534, and that widening
      `isScreenshotRun` in place was considered and refused as leaving the same trap
      for the next capture flag.
- [x] 7.3 `.abydos/backlog/spec/terminal.md` and `screenshots.md` say what the project
      now does, then re-run `openspec/extract-from-backlog.py` so `openspec/specs/`
      matches. Add any new requirement's normative line to `openspec/normative.json` —
      the extractor reports it by name if it is missing.
- [x] 7.4 Retire the workaround from 0533 and 0534 (`make build BUNDLE_ID=…` plus a
      pre-seeded defaults domain) or say why it is still needed for other reasons.
- [x] 7.5 Close backlog 0534 and 0535 together, noting that they were one defect.

## 8. What the reproductions settled

- [x] 8.1 **They are one fault, and that was established rather than assumed.**
      Reverting the follow guard alone — everything else in place — brings the
      blank sidebar straight back: 8306 bytes of empty pane against 15339 of
      project tree, twice each way. 0534's project switch and 0535's blank
      picture are the same line.
- [x] 8.2 **The blank sidebar was not caused by the exit guards**, which was the
      obvious suspect and is what the proposal implies. `--sidebar-shot` has no
      `exit(0)` in front of it; what emptied the pane was the window following
      its terminal away from the project it had been given, and then being
      photographed.
- [x] 8.3 **A second defect turned up beside it**: `--sidebar-shot` never ended
      the run. It wrote its file and sat there, so every use needed a `timeout`
      — and a run killed by one reports 124 whether or not the picture was
      written, which is how a capture that worked and a capture that hung looked
      identical. It exits now, non-zero when it wrote nothing.
- [x] 8.4 **`--editor-shot` was added earlier the same day** and is exactly the
      flag the item predicted: a capture that does not set `screenshotPath`. It
      is in `writesACapture` from the start, which is the argument against
      widening `isScreenshotRun` in place — that would have kept the trap and
      only moved it one flag along.
- [x] 8.5 **The branch order hid the rule.** "A driven run opens what it was
      given, or it fails" was the third of six branches, after the fallbacks it
      exists to prevent. It is the first now, in a function of its own, and the
      three sentences it makes are readable together.
- [x] 8.6 **A second path into the follow was reachable** (3.4):
      `onPaneNeedsProject`, which `--debug-steps` and `--run-line` both reach.
      Guarded at the same point — where the report is acted on — rather than by
      filtering what a driven run may read. `--switch-projects` is left alone: a
      verb that asks to switch is not the fault.
- [x] 8.7 **Resolving the path answers something different from what was
      expected** (6.1). `resolvingSymlinksInPath` drops a leading `/private`
      where the result exists, so both spellings converge on `/tmp/…` rather
      than on `/private/tmp/…`. Either way there is one string, which is what
      the printed line is for — checked both ways round.
