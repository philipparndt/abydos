# submodules

## ADDED Requirements

### Requirement: A checkout of submodules is read as many repositories, never as one

A project whose index holds gitlinks SHALL be read as the superproject plus one
repository per submodule, and the recursive form of `git status` SHALL NOT be
run.

`GitWorkingCopy.status(in:)` runs `git status --porcelain=v1 -unormal
--no-renames -z` in one root. In a superproject that call walks every submodule
serially inside the one process: **1.61 s for 200 submodules** of eight files
each, against **0.09 s** for the same call with `--ignore-submodules=all` — ten
cores, load averages 4.9 to 21.2, `git version 2.54.0 (Apple Git-157)`. It runs
on every filesystem event, which the code path's own comment already says is
"dozens a minute" during a build.

So two questions are asked in place of one:

- **The superproject**, with `--ignore-submodules=dirty` — 0.09 s. It reports the
  superproject's own files and every gitlink whose recorded commit has moved,
  which is what only the superproject knows.
- **Each submodule, on its own, fanned out** — 0.01 s each, **0.45 s for 200** at
  twelve concurrent. This is the working-tree detail, and it is the part that
  parallelises.

`git submodule status` SHALL NOT be used for this: it is 5.37 s for the same 200,
a process per submodule run serially, worse than the recursion it would replace.

#### Scenario: a superproject with a dirty submodule and a moved gitlink

- **GIVEN** a superproject of 200 submodules, four of them with modified files
  and one whose HEAD has moved to a commit the superproject has not recorded
- **WHEN** the working copy is read
- **THEN** the superproject call reports the one moved gitlink and none of the
  four dirty work trees
- **AND** the four dirty work trees are reported by their own repositories' calls
- **AND** no call recursed into a submodule

#### Scenario: a project with no submodules

- **GIVEN** a project whose index holds no gitlink
- **WHEN** the working copy is read
- **THEN** the inventory is empty, the estate is the one repository, and what is
  reported is what was reported before this change

### Requirement: The inventory comes from the index and is drawn before any status runs

The inventory SHALL come from `git ls-files --stage` filtered to mode `160000` —
which submodules exist, where they are, and at which commit the superproject
records them — and the overview SHALL be drawn from it before any status has been
asked for.

That call is **0.01 s for 200 submodules** and costs no process per submodule.
Reading `.gitmodules` adds the configured name and URL for another 0.01 s.

**The index decides and `.gitmodules` decorates.** A submodule removed from the
index but left in `.gitmodules`, and one added to the index by somebody whose
`.gitmodules` has not been pulled, are both ordinary mid-refactoring states. A
submodule the index names that is not on disk SHALL be shown as absent rather
than fetched, and one on disk that the index does not name SHALL be shown as
untracked.

A page that appears whole in ten milliseconds and annotates itself as the
statuses land is the difference between opening a project instantly and opening
it in half a second.

#### Scenario: opening a superproject

- **GIVEN** a superproject of 200 submodules
- **WHEN** the project is opened
- **THEN** all 200 rows exist before any submodule's status has been asked for
- **AND** each row already names its path and the commit the superproject records

#### Scenario: a submodule the index names but disk does not have

- **GIVEN** a gitlink in the index whose directory is empty
- **THEN** its row says it is not checked out
- **AND** nothing is cloned or fetched on its behalf

### Requirement: One watcher covers every submodule, and an event re-reads one repository

The estate SHALL be kept true by the two watchers the project already has, and a
filesystem event SHALL cause exactly the repositories it names to be re-read.

Every submodule's git directory lives under the superproject's own
`.git/modules/<name>` — its `.git` is a file reading `gitdir:
../.git/modules/<name>`, which is the same fact `ProjectRoot.isSubmodulePointer`
already relies on. So one `RepositoryWatcher` over the superproject's `.git` sees
every submodule's refs, HEAD and index, and one `FileSystemWatcher` over the work
tree sees every submodule's files, because a submodule's work tree is a directory
inside the superproject's.

Three hundred submodules SHALL therefore need two watchers, not six hundred.

A change under one submodule re-reads that submodule alone: **0.01 s**, against
0.45 s to sweep all 200. The full sweep SHALL run when the project opens and when
the inventory itself moves — `.git/index` or `.gitmodules` — and at no other
time.

`RepositoryWatcher.matters(directory:)` keeps its rule unchanged, and now skips
three hundred object stores rather than one.

#### Scenario: a file is saved in one submodule

- **GIVEN** an open superproject of 200 submodules whose statuses are all known
- **WHEN** a file under `svc-47` is written
- **THEN** `svc-47` is re-read and no other repository is
- **AND** the superproject is re-read only if the gitlink moved

#### Scenario: a submodule is added while the project is open

- **GIVEN** an open superproject
- **WHEN** a new gitlink is committed into the index
- **THEN** the inventory is read again and the new submodule gets a row

#### Scenario: a fetch writes thousands of objects

- **GIVEN** a fetch running in one submodule
- **WHEN** loose objects arrive under its git directory
- **THEN** nothing is re-read, because objects say nothing about any ref

### Requirement: A path is owned by the repository the longest submodule prefix names

Every git verb SHALL be run in the repository that owns the path it is given, and
which repository that is SHALL be answerable without running a process.

`GitRepository.discover(from:)` answers the superproject for every file under a
submodule, because a submodule's `.git` is a file it climbs past. Every verb
built on that answer — stage, unstage, discard, commit, diff, blame, push — is
therefore aimed at the wrong repository for any file in the estate.

Ownership SHALL be the longest submodule path that prefixes the path, and
answering SHALL cost no process, no actor hop, and no walk over the inventory:
its cost SHALL grow with the depth of the path asked about, not with how many
submodules the estate holds. Three hundred rows of a table each asking this is
the ordinary case. It SHALL answer for paths that do not exist yet, because a
newly written file under a submodule is the common case.

**`ProjectRoot`'s climbing rule is unchanged.** "You step into a submodule to
change something about the project you were already in" stays true, and is why a
terminal entering `svc-47` must not move the window. Which repository a window
follows and which repository stages a file are different questions; conflating
them is what produced the `warning: could not open directory 'sub/sub/'` failure
`Project.gitRoot` already records.

#### Scenario: staging a file inside a submodule

- **GIVEN** `svc-47/src/Main.java` modified
- **WHEN** it is staged
- **THEN** `git add` runs in `svc-47` with a path relative to `svc-47`
- **AND** nothing is staged in the superproject

#### Scenario: a file in the superproject itself

- **GIVEN** `README.md` at the superproject root modified
- **WHEN** it is staged
- **THEN** `git add` runs in the superproject

#### Scenario: a terminal steps into a submodule

- **GIVEN** a window open on the superproject
- **WHEN** a terminal changes directory into `svc-47`
- **THEN** the window does not follow it

### Requirement: The estate has one page that says where the refactoring is

There SHALL be one page listing every submodule with what changed in it, the
branch it is on, how far that branch is from its upstream, whether its recorded
commit has moved, and the state of its pull request if it has one.

A refactoring across forty services is forty branches and forty review states,
and the only thing holding them together today is a spreadsheet kept by hand.

Rows SHALL be ordered by what needs something: conflicted first, then changed,
then ahead of its upstream, then clean. Three hundred alphabetical rows of which
four matter is a page nobody reads twice.

The page SHALL remain responsive at three hundred rows. A row's contents are
computed when that repository's status lands and not while drawing, and the view
is virtualised, so three hundred rows cost what thirty do.

A row whose status has not landed yet SHALL say so rather than say clean. Nothing
in this list may read as a fact about a repository when it is a fact about what
has not been asked yet.

#### Scenario: opening the overview mid-refactoring

- **GIVEN** an estate of 200 submodules, six changed and one conflicted
- **WHEN** the overview is opened
- **THEN** the conflicted row is first and the six changed rows follow
- **AND** the remaining rows are present and say they are clean

#### Scenario: a status that has not landed

- **GIVEN** the overview drawn from the inventory before the fan-out finishes
- **THEN** rows without a status yet say so, and none of them says clean

#### Scenario: filtering to what changed

- **GIVEN** the overview of 200 submodules
- **WHEN** it is filtered to what has changes
- **THEN** only those rows remain, and the count of what was hidden is said

### Requirement: Reading the estate is bounded, and the bound is measured

Concurrent git processes SHALL be capped, and the cap SHALL be at or below the
machine's processor count.

Twelve concurrent gave **0.45 s** for 200 submodules; twenty-four gave 0.46 s.
The plateau is at roughly the core count, and past it the processes contend for
the same disk and page cache. Unbounded is three hundred processes against ten
cores while a build is running, which is how this would make the machine worse at
the job it was opened for.

A sweep SHALL be cancellable, and closing the project SHALL stop one in flight
rather than let it finish.

Any timing asserted about an estate SHALL say what the machine load was, through
`MachineLoad.said`, and SHALL assert a bound only where `Stopwatch.maySay`
permits one.

#### Scenario: opening an estate while a build runs

- **GIVEN** a build occupying the machine
- **WHEN** a superproject of 200 submodules is opened
- **THEN** no more than the cap of git processes run at once

#### Scenario: closing the project during the first sweep

- **GIVEN** a sweep of 200 submodules in flight
- **WHEN** the project is closed
- **THEN** the sweep stops and the remaining repositories are never asked
