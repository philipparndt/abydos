## 1. The one test that started it

- [x] 1.1 `readsAMessageArrivingInPieces` waits for the message rather than sleeping.
- [x] 1.2 Run the suite under deliberate load and show it green — the old one is
      reproducibly red that way, so this is testable rather than hopeful.
- [x] 1.3 The failure mode is honest: a message that never arrives fails naming that,
      not by reporting `received.uri` as wrong. Two people lost time to that.

## 2. The helper, if it earns its place

- [x] 2.1 Count how many tests want "wait until this closure has been called once, or
      fail". If it is a dozen, write it once; if it is two, do not.
- [x] 2.2 Its timeout fails the test and never returns quietly — a hang in a parallel
      suite costs the whole run.
- [x] 2.3 Its comment says why a timeout as a failure bound is not the same bet as a
      sleep.

## 3. The other 44

- [x] 3.1 Split the 45 `Task.sleep` sites into in-process and waiting-on-something-
      external. Record the split here.
- [x] 3.2 Convert the in-process ones.
- [x] 3.3 Every sleep left in place gains a sentence saying what it stands in for and
      why it cannot be awaited.

## 4. The performance bounds

- [x] 4.1 Decide between a wider bound, a smaller input, and a bound that says out
      loud it is measured inside the suite. Say which and why.
- [x] 4.2 Consider whether the fold test belongs in `make bounds` rather than
      `make test` — the Makefile's own comment already argues that timing assertions
      inside `make test` cannot separate the harness's penalty from the effect.
- [x] 4.3 Write the three measured conditions beside whatever is chosen, so the next
      person does not re-measure all three.
- [x] 4.4 Sweep the other two bounds in `PerformanceTests` the same way, since they
      were set by the same reasoning that 0472 used and this change is correcting.

## 5. Finish

- [x] 5.1 `make test` and `make warnings` both clean.
- [x] 5.2 Run `make test` several times on an idle machine and say how many were
      green. Once is not evidence for a fix to a coin toss.
- [x] 5.3 Write down what was ruled out on the way — including that raising the 200ms
      and widening the fold bound were both considered and refused as keeping the bet.
- [x] 5.4 `.abydos/backlog/spec/` only if any of this turns out to be behaviour rather
      than a test bound. Say which, either way.

## 6. What the counting found

- [x] 6.1 **The split is three ways, not two** (3.1). Of the 45 sleeps, **35 are
      the poll interval inside a bounded wait** — a deadline loop or a counted
      retry with a `break` — which is the shape being argued *for*, not against.
      **Seven are elapsed time on purpose**, where the claim is that something
      *never* happens: BrokenPipes soaks for a SIGPIPE that must not arrive,
      PipeDrain for wakeups that must stop, `ContainerImageTests` sleeps as the
      losing arm of a race, and `TerminalTests` holds reading suspended for two
      seconds because that is the test. Those cannot be waited for and now say
      so. **Three were bets**, and they were converted.
- [x] 6.2 **The helper earned its place, at three sites rather than a dozen**
      (2.1). It is kept because the two tmux ones and the three in `LSPTests`
      are the whole class 0530 is about, and because the failure it produces —
      naming what never happened — is the thing that sent two people to the
      wrong code.
- [x] 6.3 **A conversion that waited for nothing was caught by writing it out.**
      The first tmux wait asked `has-session`, and that helper hands back stdout
      without looking at the exit status — so a missing session answered with an
      empty string rather than nil and the wait returned instantly. It asks
      `list-sessions` for the name now.
- [x] 6.4 **The performance bounds needed no new mechanism** (4.1, 4.2). `make
      timing`, `Stopwatch.maySay` and `MachineLoad` already exist and already
      carry this exact argument, written when 0472 moved the warm-render bounds.
      The three bounds in `PerformanceTests` now measure every run and assert
      only when asked; `make timing` runs them serialised. Widening the bound
      and shrinking the input were both refused: each keeps the bet and only
      moves where it is lost.
- [x] 6.5 Nothing here is behaviour, so no spec sentence changes (5.4). The one
      thing that would have been — the fold bound — turned out to be a claim
      about a measurement rather than about the app.
