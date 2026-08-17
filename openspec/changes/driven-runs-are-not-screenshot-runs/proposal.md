## Why

Two properties answer the question "is this run being driven rather than used", and
the program keeps asking the wrong one.

`screenshots` defines the right one, deliberately broadly:

> A run is *driven* when it was given any `--verb` beyond the two that only say what
> to open, `--open` and `--file`. […] The rule is stated as "everything except those
> two" rather than as a list of verbs, because a list is a thing that goes out of
> date silently.

The other is one flag's presence:

    var isScreenshotRun: Bool { screenshotPath != nil }

It is asked at some twenty sites, and it means two different things at them: *"this
run is going to write a picture, so set the app up for it"* and *"`--screenshot` was
passed"*. The two coincided while `--screenshot` was the only capture flag. They
stopped coinciding, nothing noticed, and it has now cost two separate reports:

- **Backlog 0534 — a driven run showed a project nobody passed to it.** Reproduced
  five times. The window opened on the scratch project as asked, then followed its
  terminal into `~/.config/zshutil` — a shell had inherited a directory some earlier
  agent deleted, zsh fell back, `onPaneNeedsProject` fired and `switchProject` swapped
  the project out, discarding the tab `--file` had opened. `terminal` already forbids
  this. The guard is at `MainWindowController.swift:2039` and reads
  `guard !LaunchOptions.parse().isScreenshotRun else { return }` — so a driven run
  that takes no picture is not covered by a rule written for it.
- **Backlog 0535 — `--sidebar-shot` draws a blank pane unless `--screenshot` is
  passed beside it.** Whatever the capture needs from behind that gate does not happen
  for a sidebar-only run, and what comes out is an empty pane, a written file and a
  zero exit — which reads as "the sidebar had nothing in it". That is the conclusion
  0525's agent nearly wrote down.

**One defect, two symptoms.** Filed separately, merged here once extracting
`openspec/specs/` showed the spec already contained the rule that 0534 breaks and the
definition that 0535 ignores.

**This is the safety rule**, which is what makes it urgent rather than tidy. Agents
are told never to drive the app against anything under `~/dev` — copy a project into a
scratch directory and open that. All of that rests on a driven run showing the project
it was given and nothing else. 0522 exists because it already went wrong once: a verb
ran with no project named and `--type` put `C-ircle` into a file in `abydos-examples`
that nobody was editing.

## What Changes

- **The gate asks whether the run is driven.** Every site meaning "this run produces a
  picture, set the app up for it" is gated on that, not on `screenshotPath`. Where a
  site genuinely means "`--screenshot` was passed", the two questions become two
  properties, so neither can drift into meaning the other.
- **A driven run stays on the project it was given.** Following a terminal is a
  gesture, and a driven run has nobody making gestures.
- **A driven run that cannot open its named project fails visibly** — no window, a
  message on stderr, a non-zero exit — rather than opening a different one.
  **BREAKING** for any harness that relied on the silent fallback.
- **A driven run reports the project root it opened**, once, standardised — a scratch
  copy reaches the app through macOS's symlinked `/tmp`, so only the app can say which
  path it settled on.
- **`--sidebar-shot` alone produces the picture it names**, or refuses in a way nobody
  can miss.
- **The flag table is swept once** for any other capture-ish flag with the same hole,
  and what is found is named — including the finding being nothing.

## Capabilities

### New Capabilities
<!-- None. Both capabilities exist and both already say the right thing; the defect is
     that the program asks a narrower question than the one they are written in. That
     is why this was worth finding rather than worth inventing. -->

### Modified Capabilities
- `terminal`: "A window follows its terminal out of the project, and nowhere else" —
  the exception widens from a screenshot run to any driven run, and records what the
  narrower wording cost.
- `screenshots`: "A driven run opens what it was given, and types only into that"
  gains *and stays there*, a refusal when the named project cannot be opened, and a
  reported root. Two requirements are added: that a flag naming its own output
  produces it alone, and that capture setup is gated on the run being driven.

## Impact

- `LaunchOptions.isScreenshotRun` and every site that asks it — around twenty, across
  `AppDelegate`, `MainWindowController` and `ClaudeWatch`. Reading them is the work;
  the arithmetic is a line.
- `MainWindowController.swift:2039`, the follow guard, whose comment is already right
  about why it exists and wrong only in which question it asks.
- `AppDelegate.swift` — the four-branch project decision around line 244, and 0522's
  guard at line 265.
- `followsTerminalProject`, a real preference that a driven run copies into its
  volatile domain deliberately: 0522's line is about *writing*, and the reading is on
  purpose.
- Every agent-facing instruction that says to drive a scratch copy. Those become true
  rather than hopeful.
- `house-rules-an-agent-reads` (backlog 0471) states "guard every app launch" as a
  rule an agent must remember. This makes it a rule the program keeps, which is worth
  more.
