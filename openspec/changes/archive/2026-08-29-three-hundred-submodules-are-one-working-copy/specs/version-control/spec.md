# version-control

## MODIFIED Requirements

### Requirement: The working copy is shown as the folders it changed

The working copy SHALL be shown as the folders it changed.

The commit page is two trees — unstaged above or beside staged — of the folders
the changes are in, relative to the work tree root. Only folders with a change
under them are rows: the whole project would put a commit of three files at the
bottom of the tree the navigator already shows.

**Where this is shown has moved.** It was the sidebar's commit view; it is now
the commit tense of the git page in the editor area, so the list of changes sits
beside the diff of the selected one rather than above a diff opened elsewhere.
The refs tree in the sidebar shows the same folders under its working-copy row,
built from the same tree, so what is said here holds in both.

Folders come before files and then in name order, the arrangement the project
tree uses. A chain of folders with one child each stays a chain rather than
folding into one row: a folded row would not be a folder, and it would take away
the row that stages the outer folder on its own.

The trees arrive unfolded. A pane that shows five folder names where the flat
list showed twenty files has said less than it did before.

**A change carries the repository it is in.** In an estate the paths in these
trees come from several repositories, and the same folder name occurs in two
hundred of them: `src/main/java` under `svc-3` and under `svc-47` are different
folders and must not become one row. So a submodule with changes under it is a
row above its folders, named by its path, and the folders beneath it are relative
to that repository's own work tree.

**The repository row exists only where there is a repository to name.** A project
with no submodules has the trees it has always had, with no row added above them:
the estate is one repository, and a level of tree with one child that is always
the same child says nothing.

The trees arrive with the repository rows unfolded, for the reason the folders do
— though an estate large enough that two hundred repositories have changes is one
where the overview, not this tree, is the place to look.

#### Scenario: one file changed, several folders deep

- **Given** only `Sources/AbydosKit/Git/GitBlame.swift` has changed
- **When** the commit page is opened
- **Then** the unstaged tree is `Sources`, `AbydosKit`, `Git`, `GitBlame.swift`
- **And** no folder without a change under it appears

#### Scenario: the same change in the sidebar

- **Given** the same one changed file
- **When** the working-copy row in the refs tree is expanded
- **Then** the same folders are its children

#### Scenario: the same path changed in two submodules

- **Given** `src/main/java/Log.java` changed under both `svc-3` and `svc-47`
- **When** the commit page is opened
- **Then** `svc-3` and `svc-47` are separate rows, each with its own folders
- **And** neither file appears under the other's row

#### Scenario: a project with no submodules

- **Given** a project whose index holds no gitlink
- **When** the commit page is opened
- **Then** the trees begin at the folders, with no repository row above them

### Requirement: Staging a folder stages everything under it

Staging a folder SHALL stage everything under it, in the repository that owns it.

Staging or unstaging a folder acts on every change beneath it, including a
deletion, because the folder is handed to git as one path. A selection holding
both a folder and files under it hands over the folder alone.

**A folder is handed to the repository that owns it, with a path relative to
that repository.** `git add` resolves a pathspec against the repository it runs
in, so a folder inside a submodule staged in the superproject is the `warning:
could not open directory 'sub/sub/'` failure `Project.gitRoot` records. A
selection spanning several repositories is grouped by owner and staged with one
command per repository — six processes for a hundred paths across six
repositories, not a hundred.

**A submodule's own row stages that submodule's changes, not its gitlink.**
Selecting the `svc-47` row stages what changed inside `svc-47`. Moving the
superproject's gitlink is a consequence of committing there, not of staging here,
and the two are not the same act.

#### Scenario: a folder with two changed files under it

- **Given** `Sources/Git` has two changed files under it, one of them deleted
- **When** the folder is selected and staged
- **Then** both are in the index, the deletion as a deletion
- **And** the folder is no longer a row in the unstaged tree

#### Scenario: a folder inside a submodule

- **Given** `svc-47/src/main` has two changed files under it
- **When** the folder is selected and staged
- **Then** `git add src/main` runs in `svc-47`
- **And** nothing is staged in the superproject

#### Scenario: a selection spanning three repositories

- **Given** folders selected under `svc-3`, `svc-47` and the superproject
- **When** they are staged
- **Then** three commands run, one per repository, each with its own paths
