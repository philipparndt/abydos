## Why

A user's report, relayed on 2026-09-09: *"Suche in den Settings wäre toll."* A
search in the settings would be good. The maintainer agrees.

The settings window is one page — `SettingsPage`, built from
`SettingsPaneController.Row` lists, one section per subject — and it has grown
the way one page grows: Appearance, Terminal, Tools with pages under it, and the
rest, each row with a title and a sentence of help. The one-page shape was
chosen so there is one order and one place to add a setting; the price of one
long page is finding the row you mean. Every other settings window on the
machine, the system's included, answers that with a filter field at the top.

There is no originating `.abydos/backlog` item: this comes from a relayed user
report, 2026-09-09.

## What Changes

- **A filter field above the sections.** Typing narrows the page to the rows
  whose title or help contains the words, with their section heading kept so a
  row is still seen in its context; clearing it restores the page as it was.
- **Help text counts.** The sentence under a control is where the words people
  search for actually are — a row titled "Engine" is found by "ghostty" only
  through its help — so the match is over both.
- **Nothing moves.** The order is the shared section list's, filtered, so the
  window with an empty field is the window today.

## Capabilities

### New Capabilities

- `settings-search`: what a settings filter matches and what it keeps.

## Impact

- **AbydosApp**: `SettingsPage` gains the field and the filtering;
  `SettingsPaneController.describe` already lists titles and help, which is
  what a test of the match reads.
- **Driver**: a verb that types into the field and prints the rows left, so the
  claim "ghostty finds the engine row" is one a run can make.
