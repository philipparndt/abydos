# 538. Language servers eat the tool budget and Cadova is refused with a container message

> When working with cadova I get this error pretty soon in the preview panel:
> 12 tools are already running from images and none of them has finished. That
> usually means the container runtime has stopped answering.

No container is involved. A Cadova preview runs `swift run <product>` through the
user's shell, and the message names the one explanation that cannot be the cause.

## One list, two kinds of process, one counter

`ToolProcesses` has two doors and they share an array:

    public func adopt(_ process: Process) -> Bool {
        running.removeAll(where: Self.hasFinished)
        guard running.count < Self.limit else { return false }   // limit = 12
        running.append(process)

    /// Takes charge of a process that is **not subject to the cap**.
    public func track(_ process: Process) {
        running.removeAll(where: Self.hasFinished)
        running.append(process)          // same array `adopt` counts
    }

`track`'s own sentence is true only of the tracked process itself: it is never
refused. But it lands in the array `adopt` counts, so **every long-lived process
permanently spends one of the twelve slots**. A language server is started once
per language per project and stays for the session, and it never satisfies
`hasFinished`, so nothing ever reclaims its slot.

The cap's comment states the assumption that fails:

> A backstop rather than a budget: one preview pane renders one diagram at a time
> and *a project starts a handful of servers*, so nothing legitimate comes near
> this.

A handful of servers is exactly what fills it. On the reporting machine right now:
11 `sourcekit-lsp`, 13 `gopls`, 7 `rust-analyzer`, 3 each of `clangd`, `jdtls`,
`pyright` and `typescript-language-server` — not all this app's, but a project of
several languages plus a second window is over twelve on its own. Once there, the
next `adopt` fails and the first Cadova build of the session never starts.

## Why the message is worse than the refusal

`adopt` returning false is reported with `ToolProcesses.tooManyMessage`, which says
"running from images" and "the container runtime has stopped answering". For a
`swift run` that is three wrong claims in one sentence: nothing is from an image,
no container runtime is in the path, and nothing has stopped answering. Somebody
reading it goes and restarts their container runtime, which cannot help.

The refusal is also silent about *what* is holding the slots, which is the one
thing that would have made this diagnosable from the pane.

## Worth deciding

- **Two counters, or two lists.** The cap exists to stop a runaway of *short*
  tools, so it should count only those. Keeping tracked processes in a second
  array — still ended together, which is the type's real job — is the obvious
  answer, and `endEverything` then walks both.
- **Whether 12 is still right** once servers are out of it. It was chosen against
  an assumption that included them, and a Cadova build is minutes rather than
  seconds, so a pane legitimately holds a slot far longer than a diagram render.
  Say what the number is for.
- **What the message should say.** It has to name the kind of thing that is
  actually stuck, and ideally how many of each. "Twelve tools are still running"
  with a count of renders and servers is diagnosable; a claim about images is not.
  A tool that was never started from an image must not be described as one.
- **Whether a preview pane should be capped at all.** One pane already refuses to
  start a second build while one is running (`guard running == nil`), so the pane
  is self-limiting; the cap adds nothing for it except this failure. That is an
  argument for `track`-like treatment, and against it is that a pane can be opened
  many times over.

## What was decided

**Two lists, not two counters.** `tools` holds what `adopt` takes and is the
only thing `limit` is compared against; `kept` holds what `track` takes.
`terminateAll` walks both, `forget` removes from both, `isTracking(pid:)` looks
in both, and `count` is still everything held — because what that number answers
is "how many would be ended", which is not the same question as "how much of the
cap is spent". `capped` is the second number, and it is what the new test asserts
is nought after two dozen servers.

Two counters were the alternative and were rejected: a counter that is not the
list it counts is a second copy of the same fact, and `hasFinished` sweeping
means the two would have to be swept in step or drift apart silently. The list
*is* the counter.

**Twelve stays.** The number was never the fault — the population was. What it
counts now is renders, exports and builds, each with a deadline of its own and
each let go of when it ends, and one preview pane runs one at a time. So twelve
outstanding at one moment means twelve panes are all waiting, which is the
runaway the cap was written for. Raising it would have been a number picked to
feel safe with nothing behind it; lowering it would refuse work that a machine
with a dozen previews open legitimately has.

**The message is built from what is held.** It says how many tools and what kind
of work they are — `9 diagram renders, 2 Cadova builds and 1 diagram export` —
biggest group first, so the thing to go and look at is read first. The
container-runtime sentence is kept for the case it was written for and is only
added when *every* outstanding tool came from an image; a Cadova build in the
list is enough to leave it out. `adopt` therefore takes what the work is called
and whether it is in a container, because nothing downstream could work either
out: a Cadova build is `/bin/zsh -lc "swift run …"` and a PlantUML render is
`container run …`, so an executable name would have said "zsh" and "container".

`tooManyMessage` is an instance property now rather than a static one, since it
reads a state.

**A Cadova pane stays capped.** The argument for exempting it is real — one pane
refuses a second build while one runs — but the cap is per app and panes are not
scarce: the pane's own guard bounds one pane, not twenty. And a `swift run` that
hangs is exactly the shape the backstop is for. With servers out of the count
the pane has twelve slots against its own one-at-a-time build, which is room
enough that this decision costs nothing.

**Servers are not mentioned in the refusal.** They hold no slot now, so a count
of them in a sentence about what is holding slots would be the same mistake in a
politer form: a true fact placed where the reader is looking for a cause. The
list of what is running is where that question is answered, and it has a window
already.

## Ruled out

- **Sweeping the long-lived ones harder.** `hasFinished` is not the problem: a
  language server genuinely has not finished, so no sweep can reclaim its slot.
  And `hasFinished`'s own comment says why it cannot go back to `!isRunning`
  either — that sweeps out a process registered in the instant before it starts.
- **Not registering servers at all.** That is the fault this type was written to
  prevent, and it is the one thing that must not regress.
  `bothKindsAreEndedWhenTheAppEnds` fills the cap, adds four servers on top,
  ends everything, and asserts all sixteen are gone.
- **Making the message static and merely truthful** — dropping the images
  sentence and saying nothing else. It would have stopped misleading anybody and
  would still not have told them what was stuck, which is the second half of the
  report.
- **A per-kind cap** (so many renders, so many builds). Two numbers to justify
  instead of one, and no evidence that either kind runs away on its own; the
  runaway on record was renders, which is what the single number already covers.

## Steps

- [x] A project with a dozen language servers can still start a Cadova build
- [x] Long-lived processes are still ended when the app ends — that is the whole
      point of the type and must not regress
- [x] The refusal message names what is actually holding the slots and does not
      mention images or container runtimes unless one is involved
- [x] A test that fills the cap with tracked processes and shows `adopt` still
      succeeds
- [x] `make test` and `make warnings` are clean — 2855 tests in 381 suites, up
      from main's 2849 in 380, and no warnings in this repository's Swift
- [x] Write down here what was ruled out on the way
- [x] `spec/language-servers.md` says what the project now does
