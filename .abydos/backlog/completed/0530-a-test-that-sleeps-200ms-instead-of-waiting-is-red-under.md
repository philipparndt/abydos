# 530. A test that sleeps 200ms instead of waiting is red under load

`LSPFramingTests.readsAMessageArrivingInPieces` failed twice in a row during the
0529 merge and passes three times out of three when run alone. It is not the
merge's doing and it is not the LSP's: the test feeds a framed message through
`client.consume` in seven-byte slices, then does this.

    try? await Task.sleep(nanoseconds: 200_000_000)
    #expect(received.uri == "file:///a.swift")
    #expect(received.count == 1)

A fixed sleep is not synchronisation. It is a bet that 200ms is longer than the
work takes, and the suite's own parallelism is what settles the bet — the
Makefile already records this machine sitting at load 35–40 during `make test`,
and it was far above that today with three agents building at once. Under that
load the assertion arrives before the message does.

Note the failure is *silent about its cause*: it reports `received.uri` as
wrong, which reads as a framing bug in the thing under test. Two of us today
went looking at the wrong code because of it.

## The pattern, not the one test

`Task.sleep` appears **45 times** across the AbydosKit tests, in a dozen files.
Most are live tests where a sleep is standing in for a container or a language
server starting, and those are a different argument. What is worth separating is
the cases like this one, where the thing being waited for is *in this process*
and could simply be awaited or signalled.

So this item is not "raise the 200ms". Raising it trades a red run for a slow
suite and keeps the bet. What is wanted is a way for a test to wait for the
callback it is about — a continuation the `onMessage` handler resumes, an
`AsyncStream` the test reads one element from, or whatever the tree already has
for this. Then the assertion cannot run early and the test takes microseconds.

## Worth deciding

- **Which of the 45 are in scope.** The in-process ones are the cheap and
  certain wins. A live test waiting on a container may genuinely have nothing to
  await, and pretending otherwise would trade a flake for a hang.
- **Whether a helper is worth it.** If a dozen tests want "wait until this
  closure has been called once, or fail", that belongs in one place with a
  generous timeout — a timeout used as a *failure* bound rather than as the
  expected wait is not the same bet as a sleep.
- **Whether anything should assert the load.** The Makefile's comment around
  `make bounds` already argues that timing assertions inside `make test` cannot
  tell the harness's penalty from the effect they mean to detect. The same
  reasoning applies here and is worth pointing at rather than restating.

## Steps

- [ ] `readsAMessageArrivingInPieces` waits for the message rather than sleeping
- [ ] Run the suite under deliberate load and show it green — the old one is
      reproducibly red that way, so this is testable rather than hopeful
- [ ] Decide which of the other 44 are in scope and say why the rest are not
- [ ] Any shared helper is in one place, and its timeout is a failure bound
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way

## Done as an OpenSpec change

The work is in `openspec/changes/archive/2026-08-17-tests-wait-rather-than-sleep/`, and that change's `tasks.md` is
the record of what was done. The checklist above is left as it was written: the
work did not go through it, so nothing here was ticked from memory.
