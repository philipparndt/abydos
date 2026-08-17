# 531. A recipe whose output points outside is refused rather than built

GoSTL declines to preview a go3mf recipe whose `output:` is an absolute path or
climbs out with `..`, and says so in the pane:

    That names a file outside the directory this build would happen in, so
    building the recipe would write it. A viewer does not write to the project
    it is showing […] which only works for an output: that is a relative path.
    Nothing was built and nothing was written.

**That is the right refusal for the reason given, and the reason has since
stopped being true.** It stands on `go3mf` ignoring `-o` for a YAML recipe, so
the only lever GoSTL had over where the file landed was the working directory —
and a working directory cannot contain an absolute path. `go3mf` 0.16.6 honours
`-o` for a recipe (fixed in `philipparndt/go3mf`, branch
`fix/build-yaml-ignores-output-flag`), so there is now a lever that does not care
what the recipe declares: build with `-o <buildDirectory>/<basename>` and the
recipe's own `output:` never decides anything.

## Not urgent, and worth saying why

Nobody has hit this. Every recipe in `~/dev/3d` declares a plain relative
`output:`, which is what the tool's own `init` writes and what its examples show.
This is a correctness gap, not a complaint — filed because the *reason* in that
error message is now wrong, and an error that explains itself with something
untrue is worse than a terse one.

## Whose call it is

**GoSTL's, not this program's.** Abydos hands the viewer a URL and nothing else,
which is the boundary 0482 established and stayed inside. This item is a note to
carry upstream, and the shape of the change is small:
`go3mfRecipeBuildArguments` gains the `-o` it deliberately does not carry, its
comment loses the paragraph explaining why it must not, and
`go3mfRecipeOutputURL`'s nil case goes with them.

**It needs a `go3mf` floor.** Passing `-o` against 0.16.5 or older silently
writes somewhere else — which is the whole bug — so whatever does this has to
know which `go3mf` it is talking to. `findGo3mfExecutable` already locates the
binary and `go3mf version` prints one. That check is the actual work here; the
argument change is a line.

## Worth deciding

- **Whether to keep refusing anyway.** An `output:` climbing to `../../out.3mf`
  may be worth declining on the grounds that it says something surprising about
  the recipe, independent of whether the viewer *can* contain it. That is a
  different argument from the one the message currently makes, and if it is the
  one being kept then the message should make it instead.
- **What the export path does.** `openFileWithGo3mf` — the `o` key — builds
  *into* the project on purpose, and reads the declared `output:` to know what
  file to hand the slicer. It has the opposite requirement and must not be
  changed to match.

## Steps

- [ ] Decide whether the refusal goes or its message changes, and write down why
- [ ] If it goes: the `go3mf` floor is checked rather than assumed
- [ ] A recipe with an absolute `output:`, and one with `../`, both preview
      without writing outside the build directory
- [ ] The export path still writes where the recipe says
- [ ] Carried upstream to GoSTL, since it is not this program's to change
