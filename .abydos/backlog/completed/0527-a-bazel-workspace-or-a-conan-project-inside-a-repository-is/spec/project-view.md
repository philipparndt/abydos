<!-- What this item changes about `project-view`. Folded into
     .abydos/backlog/spec/project-view.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       A project shows what it depends on, beside its own files
       A dependency says which version it is and where it came from
       A kind of project this cannot read says so, on a row
       A dependency says which subproject resolved it
       A file with no place in the tree is revealed in the section
       `.build` is an ordinary folder
       A list that is read and incomplete says what is missing
-->

## ADDED Requirement: A folder a build system marks is a project of its own

A repository is often not one thing, so the folders inside it that a build
system has marked are projects in their own right: the tree stays whole,
because that is how somebody navigates, and one of them at a time can be the
part being worked on. Which folders those are is decided by the files in them —
`.git` and `.ideai`, `go.mod`, `Cargo.toml`, `package.json`, `build.zig`,
`pyproject.toml`, `CMakeLists.txt`, `Package.swift`, `pom.xml`, the Gradle
build files, `Chart.yaml`, a makefile under any of its three names, a Conan
recipe, and a Bazel workspace under any of the four names Bazel accepts. They
are looked for two directories deep, and nothing inside one of them is looked
at, because what is inside a module belongs to that module.

**One list decides five things at once**, which is what sets the bar a name has
to clear. A folder on it is offered in the menu the scope pill opens; it is
where the run configurations are read from and written to; it is the root a
language server is started on; it is the work tree git is asked about and the
directory a terminal opens in; and it is a root the **Dependencies** section
reads and gives a group row to. So a name that is right nine times out of ten
is not good enough — the tenth is an ordinary folder given a scope nobody asked
it to have, and that is a worse failure than the folder that should be a
project and is not.

Which is why a name has to *declare* a project rather than mention one. A Conan
recipe is the package: it names it, and it is what `conan create` builds, so a
folder holding one is a project with nothing else in it. A `conanfile.txt` only
says what a directory consumes — it is what sits in the `examples/` beside a
recipe — and a directory that is a project as well as a consumer has the build
file that says so and is found by that instead.

And the names are compared as names. A Mac formats a disk case-insensitively,
so asking the file system whether a `WORKSPACE` is present answers yes for any
folder with an ordinary `workspace/` directory in it; the names a folder holds
are read and matched exactly instead. A symbolic link is neither followed nor
counted, which is what keeps a built Bazel workspace from offering its own
execroot — reached through the `bazel-<workspace>` link beside `MODULE.bazel` —
as a project inside itself.

### Scenario: a Bazel workspace inside a repository

- **Given** a repository holding `services/build-farm/MODULE.bazel`
- **When** the project is opened
- **Then** `services/build-farm` is one of the projects inside it, and the
  **Dependencies** section gives it a group row of its own

### Scenario: a Conan recipe inside a repository

- **Given** a repository holding `native/fmt/conanfile.py`
- **Then** `native/fmt` is one of the projects inside it

### Scenario: a folder that only lists what it consumes

- **Given** a `samples/` folder whose only build-system file is a
  `conanfile.txt`
- **Then** it is not a project of its own
- **And** a folder holding a `conanfile.txt` beside a `CMakeLists.txt` is one,
  by the `CMakeLists.txt`

### Scenario: a folder called `workspace`

- **Given** a folder holding an ordinary directory called `workspace` and no
  build-system file
- **Then** it is not a Bazel workspace: it is not a project of its own, and it
  gets no Bazel row in the **Dependencies** section
