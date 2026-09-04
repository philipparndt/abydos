## 1. The inbox, in AbydosKit

- [ ] 1.1 `DraftInbox`: drafts keyed by standardised root path; `hold(_:for:)`, `peek(for:)`, `take(for:)`, `discard(for:)`; a later hold replaces an earlier one.
- [ ] 1.2 Tests, named as claims: a draft held for A is not found for B; taking a draft empties its slot; a second hold replaces the first; a root with a trailing slash is the same root.

## 2. The pane and the button

- [ ] 2.1 `DrawnButton.tint`: consulted by `fillColour` and `textColour`, nil everywhere today; `applyTheme` redraws on change.
- [ ] 2.2 `ChangesPane.draftState` — `.idle`, `.drafting`, `.offering` — driving label, `isEnabled`, `isWorking` and tint from one switch; `updateCommitButton()` asks the state instead of the label.
- [ ] 2.3 `draftMessage()` hands its answer to `onDraft(root, draft)` rather than to the fields; the pane applies a draft through one `apply(_:)` that fills empty fields or holds and offers; *Use draft instead* calls `fill(subject:body:)`; commit clears the offer.
- [ ] 2.4 The pane asks the inbox for its root on construction and in `restore(message:)`; `SidebarController` wires both closures at both construction sites and drains at its two `restore(message:)` sites; `showCommitPage` checks a reused page's root before handing it anything.

## 3. Proving it

- [ ] 3.1 A fake `claude` on the run's own `PATH` that answers after a chosen delay with a fixed draft, and a commit-page step `draft`; the report names the button's state and the fields.
- [ ] 3.2 Driven: draft in A, `--switch-project` to B before it answers, report B's fields and session file, switch back, report A's fields — the draft is in A and nowhere else.
- [ ] 3.3 Driven: a typed subject, draft, the button offering in red; a capture; the offer taken; commit clearing it.
- [ ] 3.4 Driven: the page-tab case — draft on the commit page, switch, return, open the page, the draft is there.

## 4. Finishing

- [ ] 4.1 Say it in the release notes.
- [ ] 4.2 `make test` and `make warnings`, both clean, both by their exit codes, with the load said.
