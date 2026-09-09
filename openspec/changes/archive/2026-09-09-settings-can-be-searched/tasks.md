## 1. The match

- [x] 1.1 The words, in the kit: what a query splits into and whether a title and help contain all of them, case-insensitively, as substrings. Tested with a title-only match, a help-only match, two words across title and help, an empty query matching everything, and a query nothing matches.
- [x] 1.2 The walk, in the app: over every flattened section's rows into groups, keeping a group whose title matches whole and a group whose rows match with those rows.

## 2. The field

- [x] 2.1 A search field in the sidebar above the sections: typing narrows the sidebar to the sections with a match and rebuilds the form as the matching rows of every one of them under its heading; clearing restores the sidebar and the selected page.
- [x] 2.2 "Nothing matched" in place of the sections when the answer is empty.
- [x] 2.3 ⌘F focuses the field: the page answers the Find menu's selector ahead of the window controller while its sidebar or form has the keyboard.

## 3. Proving it

- [x] 3.1 `--settings-filter <text>`: types into the field once the page is up and prints the sections and row titles left.
- [x] 3.2 Driven, 2026-09-09: "ghostty" leaves two rows — Appearance ▸ Terminal colours, whose help names it, and Terminal ▸ Emulate with libghostty-vt; "tmux status" leaves three, the status-bar row among them; "zebra" leaves no section and the "nothing matches" line.

## 4. Finishing

- [x] 4.1 Say it in the release notes: the paragraph is in the design, for the next `docs/release-notes-<version>.md`.
- [x] 4.2 `make test` and `make warnings`, both clean, by their exit codes. Green 2026-09-09: 4371 tests in 557 suites, exit 0 — after one run in which a pseudo-terminal descriptor test failed under load 28 beside the parallel suite and passed alone and on the rerun; `make warnings` exit 0.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where `settings-search` is new.
