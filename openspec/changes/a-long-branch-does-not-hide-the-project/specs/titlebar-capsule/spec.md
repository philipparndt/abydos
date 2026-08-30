## Purpose

What the capsule in the titlebar says about the open project and the branch it is
on, and what it does when the toolbar has less room than the two names need.

## ADDED Requirements

### Requirement: The capsule shortens what it says rather than disappearing

The capsule SHALL be no wider than its maximum, and SHALL shorten the text it
draws to stay within it.

A view in a toolbar offers one width and the toolbar treats it as a fixed demand:
an item that asks for more room than there is is moved to the overflow menu, not
compressed. So an unbounded capsule is a capsule that vanishes, and what vanishes
is the only thing in the window that says which project this is and which branch
it is on. On `admin-user-service` at `fix/dev-user-service-memory-limit` the
titlebar showed the run controls and an overflow chevron and nothing else, which
reads as an application that has failed to open anything.

This is item 0477's argument reaching the same place by another route: an unborn
branch shows its name because showing nothing was the bug.

#### Scenario: a long project name and a long branch

- **Given** a project named `admin-user-service` on the branch
  `fix/dev-user-service-memory-limit`
- **When** its window is opened
- **Then** the capsule is shown, with the project's name and a shortened branch
- **And** the toolbar shows no overflow chevron in place of it

#### Scenario: a name and branch that already fit

- **Given** a project named `git-repo` on the branch `main`
- **When** its window is opened
- **Then** both names are drawn in full, exactly as they were before there was a
  maximum

### Requirement: A shortened name keeps both of its ends

A name too long for the room it has SHALL be shortened from the middle, with an
ellipsis standing for what was left out.

A branch's two ends are the informative ones: the prefix says what kind of work
it is and the suffix says which piece of it. Shortening from the end would leave
`fix/dev-user-servi…`, which is the half a reader could have guessed from the
prefix alone, and would drop the half that identifies it.

The branch gives way before the project name does. The name is the project's
identity, and it is almost always the shorter of the two.

#### Scenario: a branch shortened in the middle

- **Given** a branch named `fix/dev-user-service-memory-limit` with room for
  about half of it
- **When** the capsule is drawn
- **Then** the text keeps the start and the end and elides the middle, as in
  `fix/dev-us…ory-limit`

#### Scenario: a project named at length

- **Given** a project whose name alone would fill the capsule
- **When** the capsule is drawn
- **Then** the name is shortened too, and the branch still has room to be read
