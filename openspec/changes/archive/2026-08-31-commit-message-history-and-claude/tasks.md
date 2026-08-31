## 1. The history control (AbydosApp)

- [x] 1.1 A history button (clock symbol) in `ChangesPane`'s summary row, present when the repository has commits, absent in a fresh repository — the amend checkbox's emptiness rule
- [x] 1.2 Opening it reads `GitHistory.log(in: root, limit: 20)` and builds the menu: subject middle-truncated with its age beside it, newest first
- [x] 1.3 Choosing an entry fills the summary with the subject and the description with the body, replacing what was typed; nothing staged, nothing committed, both fields editable

## 2. Draft becomes visible when it cannot run

- [x] 2.1 `ClaudeDraft.isAvailable` decides enabled rather than existence: the Draft button is always built, disabled with "The claude command was not found" in its tooltip when the executable is missing, re-checked when the pane refreshes
- [x] 2.2 The first-use consent and everything else drafting does stays exactly as specified

## 3. Proving it

- [x] 3.1 Driver steps on the changes pane: one that prints the history menu's titles, one that chooses an entry by index; a driven run against a scratch repository shows the last subjects newest first, chooses one, and reads both fields back filled
- [x] 3.2 The fresh-repository drive shows `history=hidden`. The claude-unfindable drive is not reachable on this machine — `ClaudeDraft.executable` searches fallback places beyond `PATH` and finds the real binary, which is the function working as designed — so the negative is carried by the existing kit claim `aMissingCommandIsAbsenceRatherThanFailure` (the injectable seam) and the five gated lines in `updateCommitButton`

## 4. Before finishing

- [x] 4.1 `make test` clean, `make warnings` clean, with the machine load said if a timing bound flakes
- [x] 4.2 No `.abydos/backlog/spec/*.md` file is made untrue: message history was unrecorded; the drafts requirement this change modifies is quoted whole in the delta
