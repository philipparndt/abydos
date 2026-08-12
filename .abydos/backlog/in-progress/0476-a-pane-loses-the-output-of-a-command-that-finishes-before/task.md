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

## What it actually is: a 600 ms deadline in the kernel

Measured, not inferred. The three instruments are in `images/` beside this file,
which is where `abydos-backlog attach` puts things; each is one
`clang -o x x.c -lutil` away from saying it again on another machine.

**A macOS pty gives unread output exactly 600 ms after the child exits, and then
discards it.** Read the master at 600 ms and the bytes are there; read it at
605 ms and the master is at EOF and they are gone. Nine runs, four delays each,
the same boundary every time:

    delay=595ms  -> bytes        delay=605ms  -> LOST (eof)
    delay=600ms  -> bytes        delay=615ms  -> LOST (eof)

`ptysweep.c` is the whole measurement: `forkpty`, the child writes and `_exit`s,
the parent sleeps a chosen number of milliseconds and then reads.

The deadline is spent inside the child's own exit. `ptyprobe2.c` has the child
write one byte down a pipe as its last instruction before `_exit`, so "finished
its work" and "finished exiting" are two separate timestamps:

       0.5ms  child reached _exit
       0.5ms  master readable
     602.0ms  master: IN HUP, child: zombie      <- output discarded here

Half a millisecond to do its work, and then **601 ms inside the kernel before it
becomes a zombie**. That wait is the kernel giving the terminal's output queue a
chance to be read. It is a grace period, not a hang: when the queue *is* read it
ends at once. Same program, parent draining the master:

       0.5ms  child reached _exit
       1.0ms  master: IN HUP, child: zombie      <- 601ms becomes 1ms

So the sequence is: the child exits, the kernel waits up to 600 ms for somebody
to take the output, then revokes the controlling terminal — which closes the last
descriptor on the slave, and closing the last slave descriptor flushes the
terminal's queues. On Linux the buffered output survives that close for the
reader; on macOS it does not, and that difference is the whole defect.

### Two things this corrects in the account above

- **Reaping has nothing to do with it.** The reading in "Reproduced, both in the
  suite and on its own" — *not waited for at all, then read: "hello-from-pty"* —
  is an artifact of reading too early. That program slept less than 600 ms. With
  no `waitpid` anywhere in it and a 3 s sleep, the answer is `NOTHING [n=0]`,
  exactly as when it reaps. `waitpid` correlated with the loss only because it
  takes about as long to return as the deadline takes to expire: the child is not
  a zombie until the deadline has passed, so `waitpid` cannot return any sooner.
  That is also why `waitid`/`WNOWAIT` measured the same — it waits for the same
  moment.
- **`FIONREAD` cannot see this.** On a pty master it answers 0 while a `read`
  would return bytes, so it is no use as an instrument here. Measured, after an
  hour of believing an empty queue.

## Why holding the slave open hung

Because it works, and the standalone program waited for the child before reading.
Holding a slave descriptor removes the deadline — the kernel then waits for the
output queue to be drained with **no bound at all**: measured out to 15 s, bytes
still there, child still not a zombie. So

- the child cannot finish exiting until somebody reads the master, and
- the program was waiting for the child to finish exiting before reading it.

Each waiting for the other, for ever. The hang was the fix working.

It is released the moment anything drains it, and by two other things as well —
measured, three runs each, because `terminate()` depends on it:

| the parent does | child reaped after |
|---|---|
| reads the master | 0.7 ms |
| closes the master | 0.6 ms |
| closes its own held slave | 0.6 ms |

And **EOF still arrives.** This item expected that holding a slave would mean the
master never reports EOF, so exit would have to be learnt from `waitpid` alone.
That is not true of a `forkpty` child: it is a session leader and this is its
controlling terminal, so when its exit completes the kernel revokes the terminal
and closes *every* descriptor on it, the parent's held one included. Measured:
the reader gets its bytes and then EOF, in every run.

## The second half: holding it is not enough if you take it too late

Holding the child's end was right and it did not fix it. Measured, the full suite
under fourteen spinners, three runs, every failure the same shape:

    attempt 5 of 20 lost the output of a /bin/echo that had already finished:
    status 0 — delivered "" — pty /dev/ttys222: child's end taken, 0 bytes in
    1 reads, read source fired 0×, child reaped 0ms after the fork, terminal
    still open — load 242.0 over 10 cores (24.2 per core)

Read it in order. `/bin/echo` exited **0**, so it ran and printed. The child's end
**was** taken. The read source fired **0 times** — nothing ever read. And the
child was already reaped by the time `start` finished, with the terminal **still
open** rather than at end of file. The only account that fits all four is that the
child wrote, exited and had its output discarded *before this process held the
descriptor that would have saved it* — and then the descriptor was taken anyway,
faithfully and far too late, onto a terminal that was already empty.

`forkpty` is what forces that. It opens the pair, forks, and **closes the slave on
the parent's side before it returns**, so the only way to get one back is to
reopen `/dev/ttysNN` by name *after* the child already exists. Between `forkpty`
returning and the next two statements running there is a thread that can be
descheduled, and at twenty runnable threads per core it is descheduled for longer
than 600 ms.

`images/window.c` makes it deterministic, by sleeping 700 ms where load would
otherwise deschedule. Three runs each, no load required:

    late   slave=held stall=700ms -> NOTHING             LOST
    early  slave=held stall=700ms -> hello-from-pty..    SURVIVED

`late` is `forkpty` and reopen afterwards. `early` is `openpty` then `fork`, so
the descriptor exists before the child does. **The descriptor is held in both.**

So the fix is `openpty` + `fork` + `login_tty`, in that order, and `fork` has to
be reached through `dlsym` because Swift's Darwin overlay marks it unavailable.
`login_tty` is precisely what `forkpty` was doing in the child — setsid, TIOCSCTTY,
the slave onto stdin, stdout and stderr — and `posix_spawn` still cannot express
it, which is why the answer is not "use posix_spawn".

### Why this took a third measurement rather than a second

Because the first fix looked like it worked, and the thing that told the truth was
an instrument rather than a rerun. `PseudoTerminal.diagnostics` is in the source
now for that reason: whether the child's end was held, how many times the read
source fired, how long the child took to be reaped, and whether the terminal was
at end of file. The first version of it asked the *descriptor* whether it was
still held, which reads "not held" every time — by the time there is an empty pane
to complain about, the terminal has been closed. An hour went on that.

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

## Estimate

2026-08-12 07:26 — another hour - the held descriptor was taken too late to help; closing the window now

## Steps

- [x] Find out when a macOS pty discards output the child has written
- [x] Find out why holding the slave open hung the standalone reproduction
- [x] Fix it: hold a descriptor on the child's end of the terminal
- [x] Put `aCommandThatIsAlreadyOverDoesNotLoseItsOutput` back, from `1c0c108`
- [x] One owner for the master descriptor, closing it once and on the read queue
- [ ] Prove it — the suite green under the load that reproduced it five times
- [ ] Write down here what was ruled out on the way
- [ ] `spec/terminal.md` says a short command's output is not lost
