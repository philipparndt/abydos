# 476. A pane loses the output of a command that finishes before anything reads it

Split out of 0472, which expected to find a timing assertion here and found a
real defect instead. **Numbered 476 and not 475 because 475 was taken while this
was being written** — `abydos-backlog new` ran in a worktree whose `main` predates
it, and reused the number. Nothing else here depends on that.

A child on a pty writes its output and exits. If nothing has read the master by
then, **the bytes are gone** — not late, gone. Whether that happens is decided by
which of two things the machine gets to first: the read source taking the bytes
out, or the thread in `watchForExit` noticing the child has finished. On a machine
with nothing to spare, the second one wins often enough to see.

Everything short is exposed, which is most of what this app runs through a pty
that is not a shell: `/bin/echo`, `abydos-icat`, a `git status`, the progress a
container build streams, a run configuration that prints one line and stops.

## How it shows

`PseudoTerminalTests.runsACommandAndCapturesOutput` — waiting on a `/bin/echo`
that costs 0.028–0.35 s alone, and failing after the full `Patience.seconds`:

| | load | per core |
|---|---|---|
| red | 124 s | 54 | 5.4 |
| red | 126.6 s | 65 | 6.5 |
| red | 124 s | 65 | 6.5 |

It has gone red at least three times and every time it was called environmental.
It is not. **The 120 s is a hang detector doing its job on a real hang** — the
output was never going to arrive, so the wait ran its whole deadline. Raising or
lowering that number fixes nothing.

## Reproduced, both in the suite and on its own

**In the suite.** 0472 added a test that runs twenty short commands and requires
each one's output, which catches in one test what the single-shot above catches
one time in many. Under `make test` with fourteen spinners beside it, at 9–26
runnable threads per core, it failed **five runs out of five** — and twice
`runsACommandAndCapturesOutput` went red in the same run with the original
symptom, `expected output after 120.0s, got: ""`. The test to add is in 0472's
branch history at commit `1c0c108`, as
`TerminalTests.aCommandThatIsAlreadyOverDoesNotLoseItsOutput`. It was **taken back
out** of that branch, deliberately: 0472's whole job was to stop the suite going
red for reasons that are not the branch under test, and landing a test that fails
under load would have undone it. It belongs to this item, with the fix.

**On its own, with no dispatch anywhere near it** — which is what says this is not
about which queue got a thread. `forkpty` a `/bin/echo`, wait for it, sleep, then
read the master:

    reaped first, nobody read yet:   NOTHING [read=0]
    not waited for at all, then read: "hello-from-pty" [read=-1 errno=35]

The second case is the same program with the `waitpid` taken out. So the bytes are
in the pty for a while and then they are not, and something about the child being
finished with is what ends them.

## Ruled out

- **Closing the master too early in `watchForExit`.** This was 0472's first
  diagnosis and it is wrong. That code does `readSource?.cancel()` and
  `close(masterDescriptor)` on `callbackQueue` — a different queue from the one
  that reads — so it looked like the obvious culprit. A fix that drains on the
  reading queue before closing was written, and **it does not help**: measured
  under the same reproduction, output was still lost. By the time `waitpid` has
  returned there is nothing left to drain. Do not spend the afternoon on it again.
- **Noticing the exit without reaping.** `waitid(P_PID, pid, &info, WEXITED |
  WNOWAIT)` leaves the child a zombie, on the theory that reaping is what tears
  the pty down. Measured: `NOTHING`, three times out of three, exactly as
  `waitpid` does. So it is not the reap.
- **The callback queue starving.** Plausible at these loads — the tests give each
  pty a fresh serial `DispatchQueue`, and a new one can wait a long time for a
  worker thread when the pool is exhausted — and ruled out by measurement.
  `ABYDOS_TERM_LOG` writes on the *reading* queue, before the hop to the callback
  queue. On the runs where attempt 10 and attempt 19 lost their output, the log is
  missing exactly `gone-9` and `gone-18` and has every other word. The bytes were
  never read, not read-and-undelivered.
- **A slow machine.** The output is `""`, never partial, and a `/bin/echo` does
  not take two minutes.

## Worth trying next

- **The parent keeping its own fd on the slave**, so the child exiting is not the
  last close of it and the pty is not torn down while output is still queued.
  `open(ptsname(master), O_RDWR | O_NOCTTY)` after `forkpty`, closed in
  `terminate()` and on the exit path. This is the standard technique and it is the
  most likely answer. A first attempt at measuring it **hung**, in the standalone
  program above, before printing — so it is not the ten-line change it looks like,
  and finding out why it hangs is the first piece of work here.
- Whatever it is, it wants to be understood rather than worked around: the
  question "when exactly does a macOS pty discard queued output" has a definite
  answer and this item should write it down.

## Also worth doing here, and not in 0472

Two things in `PseudoTerminal` that are wrong independently of this bug, found
while looking. Neither is the cause and neither was landed, because a change to
the pty's lifecycle belongs with the fix rather than beside it:

- **The master is closed from two places and neither knows about the other** —
  `watchForExit` on `callbackQueue`, and `terminate()` on whatever thread called
  it, each doing `if masterDescriptor >= 0 { close(...) }`. Closing a descriptor
  number twice is not harmless: the kernel may hand it out again in between, so
  the second close lands on a file belonging to something else.
- **The descriptor is read from four other threads while those two write it** —
  `write`, `drainOnce`, `resize`, `reportedWindowSize`, `currentDirectory`. Same
  hazard in the other direction: a read or an `ioctl` on a number that has since
  been reopened as something else.

A single owner for the descriptor fixes both. 0472 wrote one — one place that may
close it, taken with a lock so exactly one of the two callers wins, and the close
performed on the reading queue so an in-flight read has finished with the number
first — and reverted it with the rest. It is in that branch's history if it saves
any time.

## Steps

- [ ] Find out when a macOS pty discards output the child has written
- [ ] Find out why holding the slave open hung the standalone reproduction
- [ ] Fix it, whatever it turns out to be
- [ ] Put `aCommandThatIsAlreadyOverDoesNotLoseItsOutput` back, from `1c0c108`
- [ ] One owner for the master descriptor, closing it once and on the read queue
- [ ] Prove it — the suite green under the load that reproduced it five times
- [ ] Write down here what was ruled out on the way
- [ ] `spec/terminal.md` says a short command's output is not lost
