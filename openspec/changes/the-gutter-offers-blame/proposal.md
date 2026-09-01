## Why

Blame mode exists — ⌥⌘B, View ▸ Toggle Blame, a column saying who last
touched each line — and it was requested on 2026-09-01 as a missing feature,
which is the same finding the commit-drafting request made about the Draft
button: a capability nobody can find from where its question is asked might
as well not exist. "Who changed this line" is asked *at the line*, and a
right-click on the gutter today answers with the text area's menu — Go to
Definition, Cut, Paste — none of which is about the gutter.

There is no originating `.abydos/backlog` item: this comes from that direct
request.

## What Changes

- The gutter — the left area holding the line numbers — gets a context menu
  of its own. Its first entry is Show Blame / Hide Blame, the title telling
  the state, toggling the same blame mode the View menu and ⌥⌘B toggle: one
  state, another handle, the lock-and-menu pattern the secrets took.
- The text area's menu is untouched; the gutter simply stops borrowing it.
- Blame mode itself gets its first spec-level record along the way: the
  column, what it says, and that all three handles toggle one state.

## Capabilities

### Modified Capabilities

- `editor`: an added requirement — the gutter answers a right-click with its
  own menu, blame on it. (The dotenv change's open delta modifies a
  different editor requirement; the two compose.)

### New Capabilities

<!-- none -->

## Impact

- **AbydosApp**: `CodeView.menu(for:)` branches on the gutter zone it
  already hit-tests for clicks, building a small gutter menu whose blame
  item routes up the responder chain to the existing
  `MainWindowController.toggleBlame(_:)`; nothing new is loaded or drawn.
- **AbydosKit**: nothing — `GitBlame` is untouched.
- **Driver**: the editor menu is readable today via the driven menu report;
  the gutter menu gets the same treatment so the title flip is a text claim.
