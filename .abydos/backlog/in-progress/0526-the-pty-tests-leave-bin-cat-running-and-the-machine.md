# 526. The pty tests leave /bin/cat running, and the machine eventually runs out of ptys

`PseudoTerminalWriteTests` starts `/bin/cat` on a pseudo-terminal — nineteen
tests, several of them more than once — and some of those `cat` processes are
never reaped. They outlive the test run, get re-parented to `launchd`, and go on
holding their side of the pty for as long as the machine is up.

Found while working 0516, and found by the suite going red in three places that
have nothing to do with each other:

    Suite PseudoTerminalWriteTests failed
    Suite BrokenPipesTests failed
    Suite TmuxPasteTests failed

each of them failing on `terminal.start(…) → false` with `master → -1`. That is
`openpty` refusing, and the reason was two numbers:

    $ sysctl kern.tty.ptmx_max
    kern.tty.ptmx_max: 511
    $ lsof /dev/ptmx | awk 'NR>1{print $1}' | sort | uniq -c | sort -rn
      997 cat
       27 tmux

443 orphaned `/bin/cat`, the oldest started **five days** before. So this is not
a leak that shows up in one run; it accumulates over days of ordinary work until
it crosses 511, and then every terminal test on the machine fails at once, in
suites whose own code is blameless. Killing the orphans (`kill` every `cat` with
`PPID 1`) took the count to zero and the suite went from three failed suites to
2761 passed with no other change.

## Why it is worth fixing rather than sweeping up

It fails in the most confusing way available. The tests that break are not the
ones that leak — `BrokenPipesTests` and `TmuxPasteTests` are the visible
casualties — and each of them **passes when run alone**, because by then a few
ptys have been freed. So the natural reading is "flaky terminal tests", which is
what it will be written off as; and the natural response, re-running the one
suite, makes the evidence disappear. Meanwhile the real cost lands on whoever is
using the machine: 511 is a global limit, so a full pty table breaks new
terminals in the app, in tmux and in every other program on the machine, not
just the suite.

## What to look at

- `Tests/AbydosKitTests/PseudoTerminalWriteTests.swift` — which of its tests
  leave the child running. `everythingWrittenArrivesEvenWhenItIsFarTooMuch`
  writes far more than a pipe holds, so `cat` is blocked writing back when the
  test ends and may never see EOF.
- `PseudoTerminal` itself: whether closing the master is enough to make the
  child exit, and whether anything waits for it. A test that ends without
  `terminate()` and a `waitpid` leaves a process nobody will ever reap.
- Whether the fix belongs in the tests (each one tears its terminal down) or in
  the type (a `deinit` that closes and reaps). The second is better if the app
  can leak one too — worth establishing which, because a leak in the app is a
  different and larger item than a leak in the tests.

## Ruled out

Nothing yet, beyond confirming what it is: the orphans are `PPID 1` and hold
`/dev/ptmx`, the limit is `kern.tty.ptmx_max: 511`, and clearing them makes the
whole suite green.

## Steps

- [ ] Find which tests leave the child running — count `cat` before and after
      the suite
- [ ] Decide whether the tear-down belongs in the tests or in `PseudoTerminal`,
      and say why
- [ ] Establish whether the app can leak one too, or only the tests
- [ ] The suite run twice in a row leaves no `cat` behind
- [ ] Write down here what was ruled out on the way
- [ ] `spec/terminal.md` says what the project now does, if the fix changes it
