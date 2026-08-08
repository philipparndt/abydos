# 415. The verbs somebody types all day build release

`CONFIG ?= release` in the Makefile, so `make build`, `make run` and `make open`
all compile with whole-module optimisation. Measured on a quiet machine, after
touching one file:

    make build                 98 s
    make build CONFIG=debug     9.2 s

Ten to one, paid every time somebody looks at the app. `make dev` already says
`CONFIG=debug` explicitly, which is the shape of the answer and also the
evidence that this has been noticed once before and fixed in one place only.

**Why it is not just a one-word change.** Release is right for `make install`
and for anything being lived with, and this app has two things that feel it: a
Metal terminal renderer and an emulator that parses every byte a shell writes.
An unoptimised build of those is not merely slower to start — it is slower to
use, and a debug default would trade a wait somebody notices for a sluggishness
they might blame on the app instead.

So the question is which verbs mean "I am working on this" and which mean "I am
using this":

- `dev`, `run`, `open` — working. Debug, and fast.
- `install`, `release` — using. Release, whatever it costs.
- `build` — both, which is why it is the one to think about. It is the target
  the others go through, so its default is the decision.

**Worth deciding:** whether `run` and `open` pass `CONFIG=debug` and `build`
keeps release, or whether `build` flips and `install`/`release` name release
themselves. The second is fewer places and a better default for the common
case; the first cannot surprise anybody who already types `make build` expecting
a shippable app.

Either way, say the configuration in the line the script already prints, so a
ninety-second build is never a mystery while it is happening.

---

Its number is where it sits in the queue, not what it is worth doing next.
