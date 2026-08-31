## Context

The commit page (`ChangesPane`, both the sidebar column and the page arrangement) has a summary field, a description field, and — when `ClaudeDraft.isAvailable` — a Draft button beside the summary that fills both from the staged diff. `GitHistory.log(in:limit:)` already returns commits with `subject` and `body`, parsed and tested. The page has no memory of past messages: reusing one means the log page and the clipboard. `commit-message-drafts` requires the Draft control to be *absent* when the `claude` executable is not found, on the argument that a control that fails when pressed is worse than one that is not there — and the observable consequence is that on such a machine the feature does not exist to be discovered, which is how a feature this repository already has came to be requested.

## Goals / Non-Goals

**Goals:**

- The last twenty commit messages of the repository, one menu away from the
  summary field; choosing one fills summary and description.
- Filling is filling: nothing staged, nothing committed, fields editable —
  the rule drafting already keeps, kept by the history too.
- The Draft verb visible when it cannot run, disabled, naming what is missing.

**Non-Goals:**

- No memory of *typed-but-never-committed* messages (the IDE-local history
  some editors keep). The repository's log is the history that exists without
  inventing storage, it covers the reuse cases named in the request, and the
  drafts capability already preserves in-progress typing.
- No change to what drafting sends or how; `ClaudeDraft` is untouched.
- No new kit code: subjects and bodies come from `GitHistory.log`, which is
  already parsed, tested, and paid for elsewhere.

## Decisions

### The history is the repository's log, read when the menu opens

One `GitHistory.log(in: root, limit: 20)` per menu opening — not per refresh,
not cached: the menu is opened rarely and the call costs milliseconds, while a
cache is one more thing to invalidate on every commit. Ruled out: an app-side
store of messages typed into this pane (IntelliJ's model) — it needs storage,
migration and an emptiness story for every repository the app has not committed
in, and the log already holds every message that ever mattered enough to
commit. Ruled out: filtering to the current author — a teammate's message is
exactly what somebody wants to reuse the shape of, and the menu is short.

### One menu item per commit, subject shown, whole message filled

The menu shows each commit's subject (middle-truncated to menu width); choosing
fills the summary with the subject and the description with the body, replacing
what is in the fields — choosing a history entry *is* the explicit decision to
replace, unlike a refresh, which must never touch typing. Ruled out: appending
or merging — nobody wants yesterday's message concatenated onto today's half
sentence. Ruled out: a submenu preview of bodies — the subject is how a commit
is spoken about, and the body arrives in an editable field where it can be
read.

### The control sits beside Draft, and is there whenever there are commits

A history button (clock symbol, the toolbar vocabulary the app already uses
for the log) in the summary row. Absent only when the repository has no
commits — there is then no history to show, the same emptiness rule the amend
checkbox follows. It does not depend on `claude` in any way.

### Draft: disabled with a reason, not absent

`ClaudeDraft.isAvailable` stops deciding whether the button exists and starts
deciding whether it is enabled; disabled, its tooltip says the `claude` command
was not found. The spec's old argument — a control that fails when pressed is
worse than one that is not there — is kept, not overturned: a disabled control
cannot be pressed and so fails nothing. What absence actually cost was
discovery: the feature was requested by somebody whose machine hid it. The
push button already works this way (`GitPush.State.explanation` puts the
reason on the disabled verb), so this is the pane's existing pattern, not a
new one. Availability is re-checked when the pane refreshes, so installing
`claude` enables the button without a restart.

## Risks / Trade-offs

- [Choosing a history entry replaces typed text] → deliberate and explicit; the
  fields stay editable and ⌘Z in the field is AppKit's own. The menu item title
  says "Use" so the verb is plain.
- [A 20-entry menu of one-line subjects can still be missed as "history"] → the
  clock symbol plus tooltip; if it proves invisible the drafts button precedent
  says where a title would go.
- [Middle-truncated subjects can collide in the menu] → the date rides beside
  the subject the way the log page's meta line already formats it, telling two
  "Fix build" entries apart.

## Open Questions

- Whether the menu should one day include the *unpushed drafts* the pane keeps
  while typing (a "what I was writing before the window closed" entry) is left
  until the drafts capability's persistence story asks for it.
