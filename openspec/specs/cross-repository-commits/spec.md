# cross-repository-commits Specification

## Purpose
TBD - created by archiving change three-hundred-submodules-are-one-working-copy. Update Purpose after archive.
## Requirements
### Requirement: A gitlink conflict is named as two commits, not as two texts

A conflicted submodule SHALL be reported as a conflict between the two commits
each side recorded, and SHALL offer a way out that chooses a commit.

Every other conflict in this program is text, and the archived design's non-goal
— "a conflict is reported and named; resolving it is the editor's job or Fork's"
— holds for those. A gitlink is not text. No editor and no merge tool opens one:
what is in conflict is which commit of another repository this one points at, and
the resolution is a commit, not a merge.

The report SHALL name, for each side, the commit and its subject, and SHALL say
what lies between them — how many commits, in which direction, or that they have
diverged and share only an ancestor.

The ways out SHALL be: take this side's commit, take the other side's, or point
it at a third commit chosen from the submodule's own history. Each is `git add`
of the gitlink at the chosen commit.

#### Scenario: both sides moved the same submodule

- **GIVEN** a merge in which `svc-47`'s gitlink was moved on both sides
- **WHEN** the conflict is opened
- **THEN** both commits are named with their subjects
- **AND** it says how far apart they are and whether they have diverged
- **AND** taking either side stages that commit as the gitlink

#### Scenario: choosing a commit neither side recorded

- **GIVEN** the same conflict
- **WHEN** a third commit is chosen from `svc-47`'s history
- **THEN** the gitlink is staged at that commit and the conflict is resolved

#### Scenario: a submodule with a text conflict inside it

- **GIVEN** a submodule whose own merge left conflicted files
- **THEN** those are reported as the text conflicts they are, in that repository
- **AND** they are not confused with a conflict about the gitlink

### Requirement: A commit across repositories is one act that reports itself per repository

Committing the estate SHALL commit each dirty submodule with the shared message,
then stage the gitlinks those commits moved and commit the superproject; and it
SHALL record, per repository, what happened.

**It SHALL work outwards from the deepest.** A nested submodule's commit is
what moves its parent's gitlink, which is what moves the superproject's, so
committing outwards records where the inner ones were *before* they moved — a
superproject pointing at a commit that is already history the moment it is
written. A repository SHALL stage the gitlinks of whatever it holds and has just
committed, before committing itself: a gitlink is the containing repository's
index entry, so `svc/lib/leaf` is staged in `svc` and never in the superproject,
which has no such path.

Pushing SHALL work outwards for the same reason: a repository pushed before what
it points at publishes a gitlink whose commit nobody else can fetch.

**It SHALL NOT claim to be atomic.** Nothing this program can do makes two
hundred commits one transaction, and the rollback that would pretend otherwise is
`git reset --hard` in repositories somebody may already have fetched — the exact
class of operation `git-safety` refuses. A failure at repository 140 of 200
leaves 139 correct commits, and destroying them to preserve a symmetry nobody
asked for is worse than saying which 139 they are.

So each repository's outcome is one of: committed, and at which commit; failed,
and with what git said; skipped, and why. The run SHALL be resumable — repeating
it acts on what is still dirty and leaves what succeeded alone.

Pushing the estate is the same shape one step later, and reports itself the same
way.

#### Scenario: a commit across six changed submodules

- **GIVEN** six submodules with staged changes and a message
- **WHEN** the estate is committed
- **THEN** each of the six is committed with that message
- **AND** the six moved gitlinks are staged in the superproject
- **AND** each repository's new commit is named in the report

#### Scenario: a submodule inside a submodule

- **GIVEN** a superproject holding `svc-1`, which holds `svc-1/lib/leaf`, with
  changes staged in the leaf
- **WHEN** the estate is committed
- **THEN** the leaf is committed first, then `svc-1` recording where it got to,
  then the superproject recording where `svc-1` got to
- **AND** nothing is left uncommitted at any of the three levels

#### Scenario: one repository refuses the commit

- **GIVEN** the same six, one of which has a failing pre-commit hook
- **WHEN** the estate is committed
- **THEN** the other five are committed and say so
- **AND** the failing one names what git said
- **AND** running it again acts only on the one that failed

#### Scenario: nothing is left half-explained

- **GIVEN** any partial run
- **WHEN** it has finished
- **THEN** every repository in the estate has an outcome recorded against it

### Requirement: Staging and discarding act across repositories, one pathspec per owner

A selection spanning several repositories SHALL be staged, unstaged or discarded
by grouping its paths by the repository that owns each and running one command
per repository.

`git add`, `restore`, `reset` and `clean` resolve a pathspec against the
repository they run in. One command over a selection spanning three submodules
would compose the paths wrongly in all three — the failure `Project.gitRoot`
already documents, at estate scale.

Grouping also bounds the cost: a selection of a hundred paths across six
repositories is six processes, not a hundred.

Where an operation can lose work, it goes through the safety net for each
repository it touches.

#### Scenario: staging a selection spanning three submodules

- **GIVEN** changed files selected across `svc-3`, `svc-47` and the superproject
- **WHEN** they are staged
- **THEN** three `git add` commands run, one per repository
- **AND** each is given paths relative to its own repository

#### Scenario: discarding across repositories

- **GIVEN** the same selection
- **WHEN** it is discarded
- **THEN** the safety net is offered once for the whole operation
- **AND** each repository's discard is reported separately

