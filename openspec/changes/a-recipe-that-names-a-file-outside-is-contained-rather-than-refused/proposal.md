## Why

GoSTL declines to preview a go3mf recipe whose `output:` is absolute or climbs
out with `..`, and says why:

    That names a file outside the directory this build would happen in, so
    building the recipe would write it. A viewer does not write to the project
    it is showing […] which only works for an output: that is a relative path.

**The refusal is right and its reason has stopped being true.** It stood on
`go3mf` ignoring `-o` for a YAML recipe, leaving the working directory as the
only lever — and a working directory cannot contain an absolute path. `go3mf`
0.16.6 honours `-o` for a recipe, so there is now a lever that does not care what
the recipe declares.

An error that explains itself with something untrue is worse than a terse one.

## What Changes

- **The recipe's `output:` stops deciding anything.** Build with
  `-o <buildDirectory>/<basename>` and containment is a fact about the command
  rather than a property the recipe has to have.
- **The refusal goes, or its message changes to the argument actually being
  made.** An `output:` climbing to `../../out.3mf` may still be worth declining
  because it says something surprising about the recipe — but that is a different
  argument from "the viewer cannot contain it", and whichever is kept, the
  message says that one.
- **A `go3mf` floor is checked rather than assumed.** Passing `-o` to 0.16.5 or
  older silently writes somewhere else, which is the whole bug.
  `findGo3mfExecutable` locates the binary and `go3mf version` prints one; that
  check is the actual work, and the argument change is a line.
- **The export path is untouched.** `openFileWithGo3mf` — the `o` key — builds
  *into* the project on purpose and reads the declared `output:` to know what
  file to hand the slicer. It has the opposite requirement.
- **Not urgent, and worth saying so.** Nobody has hit this: every recipe in
  `~/dev/3d` declares a plain relative `output:`, which is what the tool's own
  `init` writes and what its examples show. This is a correctness gap and a wrong
  sentence, not a complaint.
- **Most of it is GoSTL's, not this program's.** Abydos hands the viewer a URL
  and nothing else, which is the boundary 0482 established and stayed inside.

## Capabilities

### New Capabilities

<!-- None. -->

### Modified Capabilities

- `previews`: *Rendering a recipe does not write into the project* is the
  requirement that carries this reasoning, and the half of it that explains why
  an absolute `output:` must be refused is the part that is now wrong.

## Impact

- Upstream GoSTL: `go3mfRecipeBuildArguments` gains the `-o` it deliberately does
  not carry, its comment loses the paragraph explaining why it must not, and
  `go3mfRecipeOutputURL`'s nil case goes with them.
- A version check around that, wherever `findGo3mfExecutable` already is.
- `openspec/specs/previews/spec.md` and `.abydos/backlog/spec/previews.md`, which
  is what this repository owns of it.
- From `.abydos/backlog` item 0531.
