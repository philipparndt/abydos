## Why

Asked for on 2026-10-24, the day `.vboard` files started opening as boards:
"we need a way to load one of the servers vboards". A team's boards live on the
server — a retro somebody started in the browser, the architecture map
everyone keeps — and Abydos can only open a board that arrives as a file. Today
the way to look at one is a browser beside the editor.

`a-vboard-file-opens-on-a-board` named this a non-goal ("the file is the
document"). Asked which of two things loading a server board should mean —
the live board in a tab, or a copy downloaded into the project and opened as a
file — the answer was the live board.

## What Changes

- **File ▸ Open vboard Board…** (and so the command palette) lists the boards
  on the server named in Settings ▸ Tools ▸ vboard, filtered as you type, and
  opens the chosen one in a tab.
- That tab is **the live board**, not a copy: no file, no edited dot, nothing
  to save, and closing it ends nothing on the server. What anybody does on it
  is on the board everyone else sees, as in a browser.
- **File ▸ Save a Copy of the Board…** writes the board in front as a `.vboard`
  wherever somebody picks, the project by default.
- Signing in, the proxy, the theme and links leaving the page work as they do
  for a board opened from a file: the same pane, without the file half.

## Capabilities

### New Capabilities

- `vboard-server-boards`: listing a server's boards and opening one live in a
  tab.

### Modified Capabilities

None in `openspec/specs`. `vboard-files` is still a change of its own; its
non-goal is pointed at this change.

## Impact

- `VboardClient` gains a board listing (`GET /api/v1/boards?q=&limit=`, the
  server's lookup for pickers) and nothing else; the copy is its existing
  export.
- `VboardPaneView` opens either a file or a board id. The navigation, download
  and dialog delegates move to a file of their own to keep it under the size
  limit.
- A new `VboardBoardPicker`, shaped like `ProcessPicker`.
- No new setting, nothing on disk, no server change.
