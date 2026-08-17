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

## What it turned out to be

Not "some of those `cat` processes". **All of them.** Counted around the suite
on its own:

    $ pgrep -fx /bin/cat | wc -l   # before
    19
    $ make test FILTER=PseudoTerminalWriteTests   # 19 tests, 6 of them start cat
    $ pgrep -fx /bin/cat | wc -l   # after
    25

Six starts, six survivors, every run. Nothing about the payload or the blocked
writer mattered; `aBacklogIsVisible`, which does almost nothing, leaked as
readily as `everythingWrittenArrivesEvenWhenItIsFarTooMuch`.

And nothing was missing from the tests. Every one of the six has
`defer { terminal.terminate() }`, `terminate()` sends SIGHUP to the child and its
group, and `watchForExit` has a thread in `waitpid` ready to reap it. All of that
ran. The child simply did not die — and would not:

    $ kill -HUP 51320 ; kill -TERM 51320 ; kill -INT 51341
    (all three still running)

**A blocked signal mask is inherited by the child of a `fork` and kept across
`execve`.** `start` forks on whichever thread called it, and under the test
runner that is a Swift concurrency worker. Asked from inside a test, its mask is

    0b11111011111111101110000000100111

— SIGHUP, SIGINT and SIGTERM all blocked, and every disposition still `SIG_DFL`,
so it is the mask and not an inherited `SIG_IGN`. `/bin/cat` therefore ran with
the hangup `terminate()` sends permanently undeliverable. It sat pending until
the test process ended, at which point the child was re-parented to `launchd`
and went on holding its pty for as long as the machine stayed up.

That is the whole of why it never dies. The second half is why it never even
falls back to dying of end-of-file, and why one leak costs more than one pty:

    cat 51320 ... 187u  CHR  16,1  0t0  41857  /dev/ttys001

`/dev/ttys001` is not that process's terminal — it is **another test's**, whose
slave descriptor it inherited and has no idea it holds. `openpty` answers with
two ordinary inheritable descriptors, and tests run in parallel, so every `cat`
started while another terminal was open took a copy of that terminal's master
and slave. Six children pinned one pty between them. A pty is freed when the
last descriptor on either end goes, so the owning terminal closing its own pair
freed nothing, the pty was never revoked, and the `cat` on it never saw
end-of-file either. When the 25 orphans on this machine were killed, 87
descriptors on `/dev/ptmx` went with them — 3.5 ptys pinned per process.

So the fix is two lines of the child's own setup, in `PseudoTerminal` and not in
the tests:

- between the fork and the exec, every disposition back to `SIG_DFL` and the
  mask emptied;
- `FD_CLOEXEC` on the master and the slave as soon as `openpty` answers.

## Does the app leak one too?

Half of it, and the worse half is the tests'. Panes are started from
`TerminalView` on the main thread, whose mask is not the concurrency pool's, so
the app was not leaking shells this way. But the descriptor half is entirely the
app's: every pane held every earlier pane's master and slave, so closing a pane
freed no pty at all, and a window open for days walked towards the same global
limit of 511. The app also handed every shell the ignored SIGPIPE that
`BrokenPipes` sets process-wide, which is why `yes | head` in a pane left `yes`
running. Both are gone with the same change.

## Ruled out

- **The tests missing a tear-down.** They are not. All six call `terminate()`
  through `defer`, and it runs. This was the first thing looked at and it is a
  dead end — `terminate()` was doing exactly what it says and being ignored.
- **`everythingWrittenArrivesEvenWhenItIsFarTooMuch` being special**, on the
  theory in the item that a `cat` blocked writing back never sees EOF. It leaks,
  but so does every other test that starts one, including the ones that write
  nothing. The payload has nothing to do with it.
- **A missing `waitpid`.** There is one, on a thread of its own, per terminal.
  The orphans were not zombies — they were *running*, which is the distinction
  that pointed at signals rather than at reaping.
- **A `deinit` that closes and reaps**, which the item suggested. It would not
  have helped: `deinit` calls `terminate()`, which is the call already being
  ignored. Reaping cannot help either, since the child has not exited.
- **Closing every inherited descriptor in the child**, which is the usual advice
  and would have covered the pipes as well as the ptys. Measured first:
  `getdtablesize()` is 245,760 here and the loop of `close` calls costs 68 ms,
  which is 68 ms added to opening every pane. `FD_CLOEXEC` on the two
  descriptors this file owns costs two `fcntl`s and fixes the pty half exactly.
  The pipes a child still inherits from Foundation are a separate item — the
  note at `ProcessPipes.swift:83` is about the same thing — and nothing about
  them exhausts a machine-wide table of 511.
- **`F_MAXFD`**, which would have made a full close cheap by naming the highest
  open descriptor. It is `#if PRIVATE` in Darwin's headers, not declared for
  anybody else, and calling it by its number answers -1.

## Estimate

2026-08-17 10:05 — the fix and the tests are in; verifying and writing up

## Steps

- [x] Find which tests leave the child running — count `cat` before and after
      the suite
- [x] Decide whether the tear-down belongs in the tests or in `PseudoTerminal`,
      and say why
- [x] Establish whether the app can leak one too, or only the tests
- [x] A test that fails on the old code: a signal reaches the child, and the
      terminal's descriptors are not inherited
- [x] The suite run twice in a row leaves no `cat` behind
- [x] Write down here what was ruled out on the way
- [x] `spec/terminal.md` says what the project now does, if the fix changes it
