## 1. The one test that started it

- [ ] 1.1 `readsAMessageArrivingInPieces` waits for the message rather than sleeping.
- [ ] 1.2 Run the suite under deliberate load and show it green — the old one is
      reproducibly red that way, so this is testable rather than hopeful.
- [ ] 1.3 The failure mode is honest: a message that never arrives fails naming that,
      not by reporting `received.uri` as wrong. Two people lost time to that.

## 2. The helper, if it earns its place

- [ ] 2.1 Count how many tests want "wait until this closure has been called once, or
      fail". If it is a dozen, write it once; if it is two, do not.
- [ ] 2.2 Its timeout fails the test and never returns quietly — a hang in a parallel
      suite costs the whole run.
- [ ] 2.3 Its comment says why a timeout as a failure bound is not the same bet as a
      sleep.

## 3. The other 44

- [ ] 3.1 Split the 45 `Task.sleep` sites into in-process and waiting-on-something-
      external. Record the split here.
- [ ] 3.2 Convert the in-process ones.
- [ ] 3.3 Every sleep left in place gains a sentence saying what it stands in for and
      why it cannot be awaited.

## 4. The performance bounds

- [ ] 4.1 Decide between a wider bound, a smaller input, and a bound that says out
      loud it is measured inside the suite. Say which and why.
- [ ] 4.2 Consider whether the fold test belongs in `make bounds` rather than
      `make test` — the Makefile's own comment already argues that timing assertions
      inside `make test` cannot separate the harness's penalty from the effect.
- [ ] 4.3 Write the three measured conditions beside whatever is chosen, so the next
      person does not re-measure all three.
- [ ] 4.4 Sweep the other two bounds in `PerformanceTests` the same way, since they
      were set by the same reasoning that 0472 used and this change is correcting.

## 5. Finish

- [ ] 5.1 `make test` and `make warnings` both clean.
- [ ] 5.2 Run `make test` several times on an idle machine and say how many were
      green. Once is not evidence for a fix to a coin toss.
- [ ] 5.3 Write down what was ruled out on the way — including that raising the 200ms
      and widening the fold bound were both considered and refused as keeping the bet.
- [ ] 5.4 `.abydos/backlog/spec/` only if any of this turns out to be behaviour rather
      than a test bound. Say which, either way.
