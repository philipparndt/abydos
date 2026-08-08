# 403. Split the build into parallel modules

**Measured, and the split is not what was wrong.** The decided first step was
to time a clean build before pulling the terminal out, on the grounds that if
the number did not move the whole plan was answered cheaply. It was answered
more cheaply than that: the number was already small, and the ninety seconds
somebody was actually waiting for came from somewhere else entirely.

On a quiet machine, `xcrun swift build`, debug:

| what                                        | wall time |
| ------------------------------------------- | --------- |
| clean, nothing in `.build` (1123 steps)      | 58 s      |
| no-op, nothing touched                       | 3.8 s     |
| one file touched in AbydosApp (`TerminalView`) | 7.1 s   |
| one file touched in AbydosKit (`Ligatures`)  | 5.3 s     |
| the same, with `--build-tests`               | 28.5 s    |

Seven seconds for a one-file change in the target the entry called too large.
Swift already recompiles the files a change reaches rather than the module, so
splitting AbydosApp into four would be moving five seconds around. The premise —
"every change recompiles all of it" — is simply not what the compiler does here,
and it was worth an hour to find that out rather than a week to act on it.

**Where the ninety seconds were.** `make build` takes `CONFIG ?= release`, so
the ordinary verbs build with whole-module optimisation:

| command                       | wall time after touching one file |
| ----------------------------- | --------------------------------- |
| `make build` (release, default) | 98 s                            |
| `make build CONFIG=debug`     | 9.2 s                             |

Ten to one, and the slow one is what `make run`, `make open` and `make install`
all inherit — every one of them a thing somebody types while working. The entry
guessed at this in its last line, under "worth timing at the same time, since it
may be most of it". It was not most of it. It was all of it.

The grammars, the other suspect, do not rebuild incrementally at all and cost
nothing here.

**What is left is a decision, not a split**, and it is somebody's to make rather
than mine: 413's sibling 415 carries it, because making `run` and `open` build
debug would trade ninety seconds against an unoptimised Metal renderer and an
unoptimised terminal, which is the sort of thing to feel before choosing.

---

Previously numbered 36, 392.
