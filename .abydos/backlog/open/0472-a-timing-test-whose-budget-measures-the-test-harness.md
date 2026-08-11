# 472. A timing test whose budget measures the test harness

`MermaidLiveTests.drawingIsFastEnoughToDoWhileSomebodyTypes` asserts `each < 0.5`
on a warm render. It went red **three times in one day** and each time it was
called environmental, correctly, and each time somebody had to stop and prove
that. Measured today, same commit, same machine:

    alone                        0.0139 s   load 16.9
    in the suite, passing        0.4619 s   load 37.3
    in the suite, failing        0.5041 s   load 37.3
    in the suite, failing        0.6050 s   load 35.0

**The suite's own parallelism is what puts the machine at load 37.** So the number
being asserted on is not the renderer's speed, it is the renderer's speed while
three hundred and fifty other suites run — and 0.46 against a 0.5 budget is not a
margin, it is a coin. Three agents building alongside made it worse, but the
passing run had none: the suite alone gets within eight per cent of failing.

The test already prints its own load, which is why every one of today's diagnoses
was quick rather than long. That instinct was right and the assertion is what
needs to catch up with it.

## The thing it is really protecting

The comment underneath says it: the decision this rests on is that a *warm* render
costs hundredths of a second where a container with no server mode to keep warm
costs about a second each. That is a **fortyfold** difference and it is the claim
worth defending. A budget of 0.5 s does not defend it — it sits between the two
answers and is closer to the wrong one. 0.0139 against 1.0 is the measurement; the
test is asserting on neither.

## Worth deciding

- **A ratio rather than a wall-clock**, which is what the claim actually is. Time
  a cold render and a warm one in the same run and assert the warm one is far
  cheaper; a loaded machine slows both and the ratio holds.
- **Or a budget with room in it.** If it stays absolute it wants to be far enough
  above the real figure to mean something — an order of magnitude below the
  container it is arguing against, rather than a hair under the number the suite
  itself produces.
- **Or take the timing out of the suite** and leave the correctness there, with
  the number behind `SCALE=1` like 0453's corpus rename. That keeps the claim
  measurable without making `make test` a lottery.
- **How many others are like this.** This is the one that fired today;
  `PseudoTerminalTests.runsACommandAndCapturesOutput` also timed out twice — 124 s
  waiting for output that takes 0.35 s, at load 54 and 65. That one is a timeout
  rather than a budget, but it has the same shape and should be looked at in the
  same pass.

Whatever is chosen, **the load line stays.** It is the reason these were diagnosed
in minutes instead of being chased as regressions.

## Steps

- [ ] Say what the claim is in numbers — warm against a container, not against 0.5
- [ ] Choose: a ratio, a budget with room, or out of the suite behind `SCALE=1`
- [ ] Do the same for `PseudoTerminalTests`, whose timeout has the same shape
- [ ] Look for others: any assertion on wall-clock in a suite that runs parallel
- [ ] Prove it — the suite green ten times over, and once under a deliberate load
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does, if anything does
