## ADDED Requirements

### Requirement: A file is opened by typing part of its path in the command palette

The command palette SHALL list files whose path matches what has been typed, and
opening one SHALL open that file in the editor.

Files join the ranked list beside projects and branches rather than taking a
prefix of their own. Somebody typing `mvnw` should not have to decide which of
four kinds of thing it is before they are allowed to type it; `>` and `:` keep
the meanings they already have.

Matching is on the whole path relative to the project, so `Git/GitRepo` finds
`Sources/AbydosKit/Git/GitRepository.swift`, and the row shows the directory
beside the name — two files called `spec.md` are told apart by nothing else.

#### Scenario: a name in the middle of a path

- **WHEN** `GitRepo` is typed in the palette
- **THEN** `Sources/AbydosKit/Git/GitRepository.swift` is listed, with its
  directory shown beside its name

#### Scenario: opening one

- **WHEN** a listed file is chosen
- **THEN** it opens in the editor and the palette closes

#### Scenario: the existing prefixes are unchanged

- **WHEN** `>` or `:` begins what is typed
- **THEN** the palette offers actions or a line number as it did before, and no
  files

### Requirement: A match in the file's own name outranks one in a directory above it

Files SHALL be ranked so that a match in the last path component comes before a
match anywhere earlier in the path.

Without this, typing a file's name buries it: a project with a directory called
`Git` answers `Git` with every file inside it, and the file actually called
`Git.swift` is somewhere in that list rather than at the top of it.

#### Scenario: the file named for the query comes first

- **GIVEN** a project holding `Sources/Git/Client.swift`, `Sources/Git/Remote.swift`
  and `Sources/Model/Git.swift`
- **WHEN** `Git` is typed
- **THEN** `Sources/Model/Git.swift` is listed before the two files in `Sources/Git`

#### Scenario: an exact name beats a longer one containing it

- **GIVEN** a project holding `Repo.swift` and `GitRepository.swift`
- **WHEN** `Repo` is typed
- **THEN** `Repo.swift` is listed first

### Requirement: The list of candidate files comes from git where there is a repository

The index SHALL be built from `git ls-files` when the project is a work tree, and
from the project walk otherwise.

Measured on a work tree of 24,691 tracked files, `git ls-files` answers in 0.03 s
where the walk takes 3.05 s for a list that differs by about nine hundred entries
— the untracked files that are not ignored. Git already knows what it is not
worth listing; the walk has to be told, and being told is what costs the three
seconds.

Where there is no repository the walk SHALL be used, and it SHALL be the same
walk `ProjectSearch` uses, with the same exclusions, rather than a second copy of
those rules.

#### Scenario: a project that is a work tree

- **WHEN** the index is built for a git work tree
- **THEN** it is built from `git ls-files` and lists the repository's tracked
  files

#### Scenario: a project that is not a work tree

- **WHEN** the index is built for a directory with no repository
- **THEN** it is built by walking the project, skipping the same directories
  `ProjectSearch` skips

#### Scenario: the exclusions are not duplicated

- **WHEN** a directory is added to the excluded directories setting
- **THEN** both project search and the palette's walk skip it, without either
  being changed

### Requirement: The index is built off the main thread and reused

Building the index SHALL NOT run on the main thread, and SHALL NOT be repeated
per keystroke.

This is the constraint the whole change is shaped by. A palette that walked
25,564 files while somebody typed would be the project switch that held the main
thread for 2,419 ms arriving through a different door, and the walk is thirty
times more expensive than either of the two that caused it.

#### Scenario: typing does not rebuild the index

- **GIVEN** a palette with its index built
- **WHEN** several characters are typed in succession
- **THEN** the index is built no more than once, and filtering happens against
  what is already in memory

#### Scenario: the main thread is not held

- **WHEN** the index is built for a project of tens of thousands of files
- **THEN** the window continues to answer while it is built

### Requirement: The palette says when the file list is not ready yet

While the index is being built for the first time, the palette SHALL say so
rather than showing no files.

An empty result reads as "there is no such file", which is a different and wrong
answer. The palette already draws headings for its sections and can say this in
the same place.

#### Scenario: typing before the index has been built

- **WHEN** a name is typed before the index is ready
- **THEN** the palette says the files are still being read, rather than showing
  nothing under that heading

#### Scenario: the list arrives while the palette is open

- **GIVEN** a palette open with the index still being built
- **WHEN** the index finishes
- **THEN** the matching files appear without the palette being reopened

### Requirement: A file created after the index was built is findable

The index SHALL be invalidated by the filesystem events the project tree already
watches.

A file saved a moment ago is exactly the file somebody is about to look for, and
an index that only refreshed when the project was reopened would be wrong most
often at the moment it is most used.

#### Scenario: a new file

- **GIVEN** an index already built
- **WHEN** a file is created in the project and the tree is told about it
- **THEN** typing its name finds it

#### Scenario: a deleted file

- **GIVEN** an index already built
- **WHEN** a file is deleted
- **THEN** it stops being listed, and choosing a file that has since gone reports
  that rather than opening an empty editor
