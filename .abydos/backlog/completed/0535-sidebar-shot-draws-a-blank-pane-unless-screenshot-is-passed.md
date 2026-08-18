# 535. `--sidebar-shot` draws a blank pane unless `--screenshot` is passed beside it

Found by the agent doing 0525, which spent captures working out why its sidebar
pictures were empty:

> `--sidebar-shot` renders a blank pane unless `--screenshot` is passed beside it
> (`isScreenshotRun` gates it)

`isScreenshotRun` is one line:

    var isScreenshotRun: Bool { screenshotPath != nil }

So it is true only when `--screenshot` was given. Whatever `--sidebar-shot` needs
that sits behind that flag does not happen for somebody who asked only for a
sidebar picture, and what comes out is a blank pane rather than an error.

## Why it is worth a number

**A flag that silently produces a wrong answer is worse than one that refuses.**
The picture is written, the exit code is fine, and the only sign is that the pane
is empty — which reads as "the sidebar had nothing in it", which is exactly the
conclusion an agent capturing a dependencies section would draw and write down.
0525's agent worked it out; the next one will spend the same captures on it.

It also fails the rule the two flags imply: `--sidebar-shot <path>` names its own
output, so it plainly means "take this picture". Needing a second, differently
named flag to make it work is a coupling nobody can guess and nothing states.

## Worth deciding

- **Which way to couple them.** `isScreenshotRun` becoming
  `screenshotPath != nil || sidebarShot != nil` is one line and makes the flag
  work alone. Whether every behaviour behind `isScreenshotRun` is *right* for a
  sidebar-only run is the actual question — it gates at least one other thing
  (`AppDelegate` skips the project panel on a capture run so nothing blocks on a
  modal), and that one clearly does apply. Read the rest before widening it.
- **Or refuse, loudly.** If the two genuinely must go together, saying so on
  stderr and exiting non-zero costs one line and cannot be misread.
- **Whether there are others.** `isScreenshotRun` is asked in more than one
  place, and any other capture-ish flag that does not set `screenshotPath` has
  the same hole. Worth grepping the flag table once rather than fixing this one
  and meeting it again. 0534 lists a driven-run flag not being recognised as a
  candidate for a different bug, so this class is already worth a look.

## Steps

- [ ] `--sidebar-shot` alone produces the picture it names, or refuses in a way
      nobody can miss
- [ ] Every behaviour behind `isScreenshotRun` is checked against a
      sidebar-only run rather than assumed to suit it
- [ ] Any other flag with the same hole is found and named here
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way

## Done as an OpenSpec change

The work is in `openspec/changes/archive/2026-08-17-driven-runs-are-not-screenshot-runs/`, and that change's `tasks.md` is
the record of what was done. The checklist above is left as it was written: the
work did not go through it, so nothing here was ticked from memory.
