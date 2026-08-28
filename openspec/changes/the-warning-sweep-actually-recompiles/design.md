## Context

See proposal.md — Why. The constraint is that this script exists to be *complete*
without paying for a cold build: eighteen grammar packages, a 20 MB generated
Kotlin parser and draw.io are five minutes of somebody else's code. So the
recompile has to be forced for this repository's targets and no others.

## Goals / Non-Goals

**Goals:**

- Two consecutive runs on the same tree give the same answer.
- A warning in a file nothing else recompiled is still reported.
- Still not a cold build.

**Non-Goals:**

- Changing which warnings are treated as ours, the length ceilings, or the exit
  codes.
- Switching the package to swiftbuild so the original path would exist. It would
  work, and it changes how everything in the repository is built to fix a
  reporting bug.

## Decisions

### Touch the sources rather than delete the objects

**Ruled out — deleting the per-target build directories.** It is the closest
thing to what the old line meant and it forces the recompile correctly the first
time. It also leaves llbuild's database describing outputs that are gone: the
second consecutive run failed the build and printed no errors, reproduced twice.
A gate that fails intermittently with nothing to read is worse than the one being
replaced.

**Ruled out — deleting the scratch path.** Correct, and the five minutes the
script was written to avoid.

**Ruled out — correcting the path to the classic layout.** `Abydos.build` exists
there too, so the one-line fix looks right, but under the classic system it holds
only the four-line executable's `main.swift.o` — nine files against
`AbydosKit.build`'s 1075. It would recompile one file and keep reporting nothing.

A touch says to llbuild exactly what is true — these files are newer than what
was made from them — and leaves its bookkeeping consistent.

### Discovered rather than listed

`Sources/*` and `Tests/*` are walked for `*.swift`. The old note wanted "no target
list to keep in step with `Package.swift`", and this keeps that: a target added
under `Sources/` is swept without anybody being told, and the vendored grammars
are excluded by having no Swift in them rather than by being named.

## Risks / Trade-offs

**The next ordinary build recompiles this repository too** → The mtimes are real,
and `.build` sees them as well as `build/warnings` does. About a minute, once,
after each sweep. Written into the script above the line so it is not a surprise,
and cheaper than a gate that cannot be believed.

**A touch changes mtimes in the working tree** → Nothing git records, and nothing
any other tool here reads. `ProjectDiscovery.lastActivity` estimates a project's
recency from git metadata mtimes rather than source files, so it is unaffected.
