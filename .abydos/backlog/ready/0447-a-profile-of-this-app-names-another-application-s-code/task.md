# 447. A profile of this app names another application's code

`sample` and `atos` cannot symbolicate this app as it is normally built. They do
not fail — **they answer, confidently, with somebody else's symbols.**

Found by 0428 while looking for what was burning eight cores. Two profiles came
back naming a *different application's* SwiftUI view types, in a plausible enough
arrangement to be believed and acted on. The finding that mattered was only
identified after rebuilding with `make build PIN_UUID=0`.

## Why

`Scripts/pin-uuid.py` pins a fixed build UUID into the binary, deliberately —
every build then has the same one. The system symbol server caches by UUID and
answers for whichever binary first claimed it, which is not necessarily this
one, and never the one you just built.

So the mechanism that makes builds reproducible makes them unprofilable, and the
failure is silent. A tool that said "no symbols" would cost a minute; one that
answers with the wrong names costs however long it takes to notice that the
functions do not exist in this repository.

## Why this matters more than it looks

Performance work here is measurement-led on purpose — 0435, 0437 and 0428 were
all settled by numbers rather than by reading — and this quietly poisons the
first tool anybody reaches for. 0446 is the next piece of performance work and it
starts by profiling exactly this app.

## Worth deciding rather than assuming

- **Whether the pin is needed at all for a local build.** It exists so a release
  can be matched to its crash reports; a debug build somebody is profiling has no
  such need, and `PIN_UUID=0` already exists as the escape hatch.
- **Whether `make dev` and `make run` should stop pinning**, leaving `build` and
  `release` as they are. That would make the default development build
  profilable and leave the reproducible one alone.
- **Whether the tools can be made to say so.** If a stale UUID can be detected —
  comparing what `atos` answers against a symbol known to be in this binary —
  then a line in `make perf`, or in the profiling instructions, is worth more
  than a change in behaviour.

Not investigated: whether `dsymutil`, a fresh `dSYM`, or clearing the symbol
cache is enough to make a pinned build symbolicate honestly.

## Steps

- [ ] Reproduce: profile a pinned build and an unpinned one, and show the two
      answers side by side in this entry
- [ ] Decide which builds pin, and say why in `Scripts/pin-uuid.py` itself
- [ ] Make the wrong answer loud, if it can be detected at all
- [ ] Say where somebody profiling this app should start, where they will look
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does, if anything a user
      sees changed — it may not, and then say so
