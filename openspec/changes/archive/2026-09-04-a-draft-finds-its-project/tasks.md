## 1. The inbox, in AbydosKit

- [x] 1.1 `DraftInbox`: drafts keyed by standardised root path; `hold(_:for:)`, `peek(for:)`, `take(for:)`, `discard(for:)`; a later hold replaces an earlier one.
- [x] 1.2 Tests, named as claims: a draft held for A is not found for B; taking a draft empties its slot; a second hold replaces the first; a root with a trailing slash is the same root.

## 2. The pane and the button

- [x] 2.1 `DrawnButton.tint`: consulted by `fillColour` and `textColour`, nil everywhere today; `applyTheme` redraws on change.
- [x] 2.2 `ChangesPane.draftState` — `.idle`, `.drafting`, `.offering` — driving label, `isEnabled`, `isWorking` and tint from one switch; `updateCommitButton()` asks the state instead of the label.
- [x] 2.3 `draftMessage()` hands its answer to `onDraft(root, draft)` rather than to the fields; the pane applies a draft through one `apply(_:)` that fills empty fields or holds and offers; *Use draft instead* calls `fill(subject:body:)`; commit clears the offer.
- [x] 2.4 The pane asks the inbox for its root on construction and in `restore(message:)`; `SidebarController` wires both closures at both construction sites and drains at its two `restore(message:)` sites; `showCommitPage` checks a reused page's root before handing it anything.

## 3. Proving it

- [x] 3.1 **A `deliver` step rather than a fake `claude`, agreed 2026-09-04.**
      What is under test is where an answer *goes* — the inbox, the pane's own
      root, the fill-or-offer rule — and none of that is `claude`'s.
      `deliver:summary|description` hands the pane a draft through the same
      closure the real answer comes through; a fake executable would add a
      shell script, a `PATH` to manage and a subprocess to every run to
      exercise code that has its own tests. `draft` presses the button and
      `draft-report` names the state, the label, the tint, both fields and
      whether the inbox is holding anything.
- [x] 3.2 Driven, and it is the report in one run: p1's page empty, switch to
      p2, `DRAFT: held for p1; window is on p2` — and p2's page reads
      `summary=[] body=[]`, so p1's words did not land in it — then back to p1,
      where the fields hold `feat: drafted for p1` and the inbox is empty
      again.

      **The session-file half cannot be driven**, since a driven run writes no
      session; the fields being empty is the observable half, and the kit tests
      cover the keying.
- [x] 3.3 Driven: a typed subject, a draft delivered, then the offer taken —
      `offering / Use draft instead / red / summary=[my own subject] / body=[]`
      and then `idle / Draft / none / summary=[feat: drafted] /
      body=[Why it changed.]`. The empty body in the first line is the old
      fault gone: a typed subject used to take the draft's description and drop
      its summary.

      **It caught the offer being unpressable.** The consent guard for sending
      diffs ran before the offering branch, so pressing an offer asked to send
      instead of writing in an answer already in hand.
- [x] 3.4 The page-tab case is the same run: the draft was asked for and read
      on the commit *page*, the switch closed its tab, and the page reopened on
      return holds the draft. A page left from another project is no longer
      reused for it either — `showCommitPage` checks its root, which it did not.

## 4. Finishing

- [x] 4.1 Said in the 0.12.0 notes, which is the file the newest commits are still adding to.
- [x] 4.2 `make test` 4053 tests in 516 suites, exit 0, in 51.7 s on a quiet
      machine; `make warnings` exit 0. The size ratchet caught
      `MainWindowController+Driving.swift` crossing the hard 1100-line limit —
      the driving verbs' own overflow file took the new one.
