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
