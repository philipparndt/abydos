## Why

On `admin-user-service`, checked out on `fix/dev-user-service-memory-limit`, the
titlebar showed no project name and no branch at all — just the run controls and
an overflow chevron. It was reported as "for the following path which is a git
repo no title is shown at all".

Nothing was failing to load. The capsule's width is
`max(minimumWidth, projectWidth + branchWidth)` and nothing bounds it above, so
eighteen characters of project name plus thirty-two of branch made an item wider
than the toolbar could host — and a toolbar that cannot fit an item does not
shrink it. It moves the item to the overflow menu and leaves a chevron. So the
one item that says *which project this is and which branch it is on* was the
first thing to disappear, and on a long-named repository it disappeared every
time.

Photographed both ways in the same window: `git-repo` on `main` shows
`git-repo │ main ⇧⌘P`, and `admin-user-service` on
`fix/dev-user-service-memory-limit` shows nothing. Reproduced on a clean tree
with the reporter's change stashed, so it is not new.

There is no backlog item. Item 0477 is the nearest relation: it decided that an
unborn branch shows its name because "showing nothing was the bug", and this is
the same argument arriving by a different route.

## What Changes

- The capsule has a maximum width, and shortens what it draws rather than
  growing past it, so the toolbar never has cause to hide it.
- A branch too long for the room is shortened **from the middle** —
  `fix/dev-us…ory-limit` — because a branch's two ends are the informative ones:
  the prefix says what kind of work it is and the suffix says which piece.
- The project name is held to a share of the capsule for the same reason, so a
  folder named in a sentence cannot take the room the branch needs. No ordinary
  name reaches this.
- Unchanged: a project and branch that already fit are drawn exactly as before,
  untruncated. Confirmed by photograph.
- Unchanged: the item's `visibilityPriority` stays `.standard`. Something has to
  give in a narrow window, and the argument for the switcher going first — it is
  in the menu bar too — is sound. What was wrong was going first at a width where
  it would have fitted.

## Capabilities

### New Capabilities

- `titlebar-capsule`: what the capsule in the titlebar says about the project and
  its branch, and what it does when there is not room for all of it.

### Modified Capabilities

None. No existing capability describes the titlebar. `openspec/specs/tab-overflow`
is the nearest neighbour — the same "does not fit" question asked about editor
tabs — and says nothing about the toolbar.

## Impact

- `Sources/AbydosApp/Titlebar/TitlebarCapsule.swift` — a maximum width, the two
  shortened strings, and drawing what was measured rather than the full text.

No other file. The toolbar item, its priority and its menu representation are
untouched.
