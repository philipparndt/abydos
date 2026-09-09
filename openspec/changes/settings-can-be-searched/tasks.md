## 1. The match

- [ ] 1.1 A pure function over `[Section]`: given the words typed, which sections and rows remain, walking into `Row.group`. Tested with titles-only and help-only matches, two words across title and help, and an empty query returning everything.

## 2. The field

- [ ] 2.1 A filter field above the sections in `SettingsPage`, hiding row containers and section headings by the function's answer; clearing un-hides. Nothing rebuilt, nothing re-ordered.
- [ ] 2.2 "Nothing matched" in place of the sections when the answer is empty.
- [ ] 2.3 ⌘F focuses the field, if the design's open question lands there.

## 3. Proving it

- [ ] 3.1 A driven verb that types into the field and prints the sections and row titles left, through `SettingsPaneController.describe`.
- [ ] 3.2 Driven: "ghostty" leaves the engine row under Terminal; "tmux status" leaves the rows containing both; clearing prints the whole page in its order.

## 4. Finishing

- [ ] 4.1 Say it in the release notes.
- [ ] 4.2 `make test` and `make warnings`, both clean, by their exit codes.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where `settings-search` is new.
