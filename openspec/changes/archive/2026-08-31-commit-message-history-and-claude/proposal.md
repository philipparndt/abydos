## Why

Half of this request already exists and is worth saying out loud: the commit
page drafts a message with Claude from the staged diff, seeded with this
repository's own subjects — `commit-message-drafts` has specified it since it
was written, and the Draft button sits beside the summary field. But the
button is *hidden entirely* when the `claude` executable is not found, so on a
machine where locating it fails the feature does not exist to be asked about —
which is presumably how it came to be asked for on 2026-08-31. A verb that
vanishes teaches nobody what the page can do.

The other half is new: there is no history of commit messages. A message like
the last one — a repeated chore, a second try after an amend gone wrong, the
same subject shape as yesterday's — has to be retyped or fished out of the log
page by hand.

There is no originating `.abydos/backlog` item: this comes from that direct
request.

## What Changes

- The commit page offers the repository's recent commit messages: a history
  control beside the summary field opens a menu of the last twenty subjects,
  and choosing one fills the summary and description fields with that commit's
  full message.
- Filling from history is filling fields, nothing more — the same rule
  drafting already keeps: nothing staged, nothing committed, both fields still
  editable.
- The Draft button stays visible when `claude` cannot be found — disabled,
  with a tooltip saying what is missing — instead of vanishing. A grey verb
  that names its requirement is how the feature gets discovered; today's
  absence is how it got requested twice.
- No change to what drafting does; `ClaudeDraft` is untouched.

## Capabilities

### New Capabilities

- `commit-message-history`: the recent messages a commit page offers, what
  choosing one fills, and what it never does.

### Modified Capabilities

- `commit-message-drafts`: one requirement modified — drafting-not-offered
  becomes drafting-visibly-unavailable when the executable is missing (the
  nothing-staged case keeps its behaviour).

## Impact

- **AbydosKit**: none expected — `GitHistory.log` already carries subjects and
  bodies, tested; the menu is presentation.
- **AbydosApp**: `ChangesPane` grows the history control beside the Draft
  button, a menu built from `GitHistory.log(in:limit:)`, and the fill action;
  the Draft button's availability handling changes from hidden to disabled
  with a reason.
- **Driver**: the menu's titles and the fill are made readable/firable the way
  the pane's other menus are, so a driven run can prove the fill.
- **Cost**: one `git log -20` when the menu is opened, not per refresh.
