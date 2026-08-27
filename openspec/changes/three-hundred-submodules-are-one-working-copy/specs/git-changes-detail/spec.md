# git-changes-detail

## ADDED Requirements

### Requirement: A gitlink says how far its commit moved, not how many lines changed

A changed gitlink SHALL read as the commits between where the superproject
records it and where it now points, and SHALL NOT be given a line count.

`A changed row says how much changed` gives every changed row a `+n −m`. A
gitlink has no lines: the whole of its content is one object name, and a diff of
it is one line removed and one added whatever happened underneath. `+1 −1` for a
submodule that advanced by forty commits is a true number that says nothing.

So the count for a gitlink is commits: `12 ahead`, `3 behind`, or that the two
commits have diverged and share only an ancestor. The subject of the commit it
now points at is what the row says beside that, because it is the sentence that
identifies where the submodule has got to.

**A gitlink whose submodule is also dirty says both**, and does not confuse them.
"This submodule points somewhere new" and "this submodule has uncommitted work"
are different facts about the same row, and a refactoring produces them in that
order.

**A gitlink SHALL NOT be counted into its parent folder's line totals**, for the
same reason it has none of its own.

#### Scenario: a submodule advanced by twelve commits

- **GIVEN** `svc-47` pointing twelve commits ahead of what the superproject records
- **WHEN** the changed-file tree is drawn
- **THEN** its row reads twelve ahead and names the subject it now points at
- **AND** it carries no line count

#### Scenario: a recorded commit the submodule has never fetched

- **GIVEN** a gitlink at a commit that is not in the submodule's object store
- **THEN** the row says the commit is not here
- **AND** it does not read as no movement at all

#### Scenario: a submodule that has diverged

- **GIVEN** a gitlink whose recorded and current commits share only an ancestor
- **THEN** the row says they have diverged rather than giving a direction

#### Scenario: a submodule both moved and dirty

- **GIVEN** `svc-47` moved three commits ahead and holding two modified files
- **THEN** the row says both, as two facts

### Requirement: Asking how much an estate changed costs one question per changed repository

The counts shown for an estate SHALL be gathered with one command per repository
that has changes, and no command for a repository that has none.

`Asking how much changed does not make a repository slow to read` is the existing
rule for one repository. Across two hundred, the way to break it is a numstat per
repository whether or not it changed — two hundred processes to annotate six
rows.

The superproject's own status already names which gitlinks moved, at 0.09 s with
`--ignore-submodules=dirty`, and the estate already knows which submodules are
dirty. Both sets are known before any count is asked for, so the counts are asked
only where there is something to count.

Commits between two gitlink commits SHALL be counted with one `git log
--left-right` per changed repository, which answers both directions, divergence
and the subject it now points at in a single call.

**A recorded commit the submodule does not have SHALL be said, not counted.**
It is what an estate looks like before somebody fetches, and git refuses the
question outright — `fatal: Invalid symmetric difference expression` — so the
row says the commit is not here rather than showing a movement of nought.

#### Scenario: six changed submodules out of two hundred

- **GIVEN** an estate of 200 submodules, six with changes
- **WHEN** the changed-file tree is drawn with its counts
- **THEN** six commands are run, one per changed repository
- **AND** none is run for the 194 that are clean
