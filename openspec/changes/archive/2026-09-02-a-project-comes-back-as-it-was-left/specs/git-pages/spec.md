# Git pages — delta

## ADDED Requirements

### Requirement: A page restored by a session comes back on what it was showing

A git page reopened from a session SHALL come back on what it was showing, not
merely open: the log page on its ref and its file scope, the stash page on the
stash it was showing, named by ref rather than by index — an index is a different
commit after one `git stash push`.

A page reopened blank is a page somebody has to find their way back into, which
is most of the cost of having lost it.

Where what a page was showing is gone — a stash popped from another window — the
page SHALL be left closed rather than opened empty.

A restored page SHALL read the repository as it is now. It is reopened through
the openers a click uses, which are idempotent: a restore that races somebody
opening the same page SHALL NOT produce two of it.

#### Scenario: a scoped log page

- **GIVEN** a log page scoped to one file
- **WHEN** the project is left and returned to
- **THEN** the log page is open, scoped to that file

#### Scenario: a stash that is gone

- **GIVEN** a session naming a stash page whose stash has since been popped
- **THEN** no stash page is opened
