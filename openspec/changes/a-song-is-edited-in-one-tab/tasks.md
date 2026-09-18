## 1. A tab that shows more than one file

- [x] 1.1 `Tab.url` is the file in front and `Tab.song` is what the tab is;
      `Tab.Half` holds the per-file state and moves in and out.
- [x] 1.2 The per-file construction comes out of `makeTab` as `makeCodeSource`
      and `wire(_:of:document:in:)`, so a tab can build another file's half —
      and a file's own callbacks act on that file rather than on the tab's name
      for it.
- [x] 1.3 `showInTab(file:in:)`: the half swaps where the outgoing view sits —
      inside the split, inside the crumb row's stack, or as the tab itself.
- [x] 1.4 The server is told about each file as it is shown, and about every one
      of them when the tab closes.

## 2. Saying where you are

- [x] 2.1 `SongFilesBar`: the song, a menu of its files with a tick on the one
      in front, and the trail to it. The chevron is a symbol, centred.
- [x] 2.2 The row is refreshed when the song's files arrive from the server.

## 3. Getting there

- [x] 3.1 `open(fileURL:)` shows a song's file in the song's tab, from the tree,
      a definition jump or a driven step.
- [x] 3.2 A cold-opened file whose song the server names turns its tab into that
      song's tab.
- [x] 3.3 In-tab moves are recorded in the navigation history, so ⌘[ comes back.
- [x] 3.4 A go-to-definition that finds nothing says so.

## 4. Proving it

- [x] 4.1 Driven `tabs` step: the group's tabs and the file in front.
- [x] 4.2 Driven walk on the drive example: song → drums → parts/bass → song,
      one tab throughout, `runs=1`, playing the whole way, recorded in the
      design.
- [x] 4.3 Release notes.
- [x] 4.4 `make warnings` clean (exit 0). `make test`: 4535 tests passed at load
      66; a later run at load 227–299 lost nine live tests to exporter
      timeouts ("The page did not answer within 120 seconds"), and those four
      suites pass on their own — 31 tests in 3.0 s at load 148–166.
