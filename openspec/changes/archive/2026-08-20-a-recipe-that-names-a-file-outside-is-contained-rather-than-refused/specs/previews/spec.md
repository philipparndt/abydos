## ADDED Requirements

### Requirement: A recipe is contained by the command that builds it, not by what it declares

A recipe SHALL be previewed into the build directory whatever its `output:`
says, because the build is given `-o` and the recipe's own declaration decides
nothing.

The preview used to refuse an `output:` that was absolute or climbed out with
`..`, on the grounds that the working directory was the only lever it had and a
working directory cannot contain an absolute path. That was true while `go3mf`
ignored `-o` for a YAML recipe. It stopped being true in 0.16.6, and an error
that explains itself with something untrue is worse than a terse one.

**Passing `-o` SHALL depend on the version answering for it.** Against 0.16.5 and
older the flag is ignored and the file is written somewhere else silently, which
is a worse failure than the one being fixed — so an older tool SHALL keep the
refusal.

**The export path SHALL be unaffected.** Building a recipe *into* the project and
handing the result to a slicer is a different verb with the opposite requirement,
and it reads the declared `output:` on purpose.

#### Scenario: a recipe naming an absolute path

- **GIVEN** a recipe whose `output:` is an absolute path, and a `go3mf` that
  honours `-o`
- **WHEN** it is previewed
- **THEN** it renders, and nothing is written outside the build directory

#### Scenario: a recipe climbing out

- **GIVEN** a recipe whose `output:` begins `../..`
- **THEN** the same

#### Scenario: a tool too old for the flag

- **GIVEN** a `go3mf` older than 0.16.6
- **WHEN** such a recipe is previewed
- **THEN** it is refused as it is today, rather than built somewhere unexpected

#### Scenario: exporting is not previewing

- **GIVEN** any of those recipes
- **WHEN** it is built for a slicer rather than for the viewer
- **THEN** it is written where the recipe says

## MODIFIED Requirements

### Requirement: Rendering a recipe does not write into the project

Rendering a recipe SHALL NOT write into the project.

A recipe names the file it produces — `output:` is not optional, and a recipe
without one is refused by the tool that reads it. So rendering one has somewhere
it wants to put a `.3mf`, and that somewhere is beside the source unless
something decides otherwise.

**Showing a file never modifies what it is showing.** The render happens in a
build directory of the viewer's own, and **the build is told to write there**:
the recipe's own `output:` is used for its file name and decides nothing else,
so the `.3mf` sitting next to the recipe — quite possibly one made by hand — is
left as it is whatever the recipe declares.

This is the sentence that changed. A recipe whose `output:` was absolute, or
climbed out with `..`, used to be refused rather than rendered, because the
working directory was the only lever the viewer had and a working directory
cannot contain an absolute path. The tool honours `-o` for a recipe from 0.16.6,
so containment is a property of the command now and there is nothing left to
refuse — **except against an older tool**, which ignores the flag and writes
where the recipe said. That case SHALL still be refused, and the refusal SHALL
say that it is the tool's age rather than a limit on what a viewer can contain.

#### Scenario: a recipe that names a file beside itself

- **Given** a recipe with `output: adapter-set.3mf`, and an `adapter-set.3mf`
  already beside it
- **When** the model is asked for
- **Then** the model is shown, and the file beside the recipe is untouched

#### Scenario: a recipe that names somewhere outside

- **Given** a recipe whose `output:` is an absolute path or begins `../`
- **When** the model is asked for
- **Then** the model is shown, and nothing is written where the recipe pointed

#### Scenario: a tool too old to be told

- **Given** a `go3mf` older than 0.16.6, which ignores `-o` for a recipe
- **When** such a recipe is asked for
- **Then** nothing is written and the viewer says the tool is too old, rather
  than writing where the recipe pointed
