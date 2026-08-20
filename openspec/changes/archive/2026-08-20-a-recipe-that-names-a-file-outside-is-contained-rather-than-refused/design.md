## Context

Two paths build the same recipe and want opposite things.

**The preview** must not write into the project it is showing: it renders into a
build directory of its own. It could only control where the file landed by
choosing the working directory, because `go3mf` ignored `-o` for a YAML recipe —
so a recipe naming an absolute path escaped containment, and the honest response
was to refuse it and say why.

**The export** — the `o` key, `openFileWithGo3mf` — builds *into* the project
deliberately, and reads the declared `output:` so it knows which file to hand the
slicer.

`go3mf` 0.16.6 honours `-o` for a recipe. The preview now has a lever the recipe
cannot argue with; the export still wants the recipe's own answer.

## Goals / Non-Goals

**Goals:**

- The preview contains every recipe, whatever its `output:` says.
- No message explains itself with a reason that is no longer true.
- The version that makes this safe is checked, not assumed.

**Non-Goals:**

- Changing the export path, which has the opposite requirement.
- Making Abydos build recipes itself. It hands the viewer a URL; 0482 settled
  that boundary and this stays inside it.
- Fixing anything nobody has hit. This is a wrong sentence and a gap.

## Decisions

**Containment becomes a property of the command, not of the recipe.**
`-o <buildDirectory>/<basename>` decides where the file lands regardless of what
the recipe declares, which is what makes the refusal unnecessary rather than
merely unfriendly.

**The refusal is not simply deleted; the argument is re-decided.** There is a
second, independent case for declining `../../out.3mf` — a recipe that says
something surprising is worth stopping over even if the viewer *can* contain it.
Whichever is chosen, the message must make the argument being made. Ruled out:
keeping the refusal with its current wording, which is the one option that is
certainly wrong.

**The floor is checked before `-o` is passed.** Against 0.16.5 and older,
passing it silently writes somewhere else — a worse failure than the one being
fixed, because it is invisible. `go3mf version` is what answers it, and
`findGo3mfExecutable` already has the binary in hand.

**It is carried upstream rather than worked around here.** The change is in
GoSTL's argument construction. This repository's share is the requirement's
reasoning and whatever floor it wants to state.

## Risks / Trade-offs

- **A version check on a drawing path.** → It is on the build, which is already a
  subprocess, and answers once per binary rather than per render.
- **An old `go3mf` on somebody's machine.** → It keeps today's behaviour: refuse,
  and say so. That is the safe branch and is why the check comes first.
- **Two paths, two `output:` meanings.** → They are already two functions with
  opposite comments; this widens the difference and is worth a sentence in the
  spec so the next reader does not unify them.

## Open Questions

- **Does the refusal survive on the second argument?** Nobody has hit the case,
  so there is no report to decide it either way.
- **Where does the floor live** — a constant in GoSTL, a sentence in this
  project's spec, or both?
