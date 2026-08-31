## Why

`make warnings` reported "No warnings in this repository's Swift. Keep it that
way." and exited 0, on a tree that a wiped scratch path showed had two —
`SidebarController.swift:340` and `:351`. The gate was open and said it was shut.

`Scripts/warnings.sh` removes one directory to force the recompile that makes its
answer complete:

    rm -rf "$SCRATCH/out/Intermediates.noindex/Abydos.build"

**That path does not exist.** It is where swiftbuild puts a package's objects;
under the classic build system they go to
`$SCRATCH/<triple>/<config>/<target>.build`, one directory per target, with no
single one holding the package. So the `rm -rf` matched nothing, nothing was
recompiled, and the sweep reported only what something else had happened to
rebuild. On a warm scratch path that is usually nothing at all.

This is the failure item 0465 wrote the script to prevent — "an incremental build
only reports the files it recompiled, so a warning is seen once by whoever
happens to be watching and then never again" — arriving inside the script itself.
It was found while checking a `make warnings` result that disagreed with an
earlier run on the same tree.

## What Changes

- The recompile is forced by making this repository's sources newer than their
  objects, rather than by deleting a directory that is not there.
- **Not by deleting the target directories either**, which does force the
  recompile and also breaks: llbuild keeps a database of what it built, and
  outputs removed behind its back leave it in a state where the next run fails
  with no errors to print. Observed on the second consecutive run, twice.
- Nothing anybody else's is recompiled: `Sources/Grammars` holds vendored
  upstream C, which has no `.swift` in it and so falls outside the pattern rather
  than outside an exclusion list somebody has to maintain.
- The cost is written into the script: the next `make build` or `make test` also
  recompiles this repository, because their scratch path sees the same mtimes.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. `make warnings` is a build tool rather than behaviour of the app, and no
capability under `openspec/specs` describes it. `.openspec.yaml` sets
`skip_specs: true` for that reason.

## Impact

- `Scripts/warnings.sh` — the one step that forces the recompile, and the note
  above it explaining what was wrong with the old one.

No source file, no test, and no behaviour of the app. What changes is whether the
gate can be believed.
