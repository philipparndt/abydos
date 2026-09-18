## Why

Asked for 2026-09-16, after a day of working in songs written across several
files: "jumping to other files and keep the stream does not really work … It
stops very often and also it cannot know to which song it belongs. Lets say we
have a library with snippets, who should it know."

A song is one thing written across files — a kit of instruments, a set of
patterns, the song that includes them — and it is the *song* that plays. Until
now each of those files opened as a tab of its own with a song pane of its own,
and that pane had to work out which song the file belonged to: it asked the
language server, waited a moment and then re-pointed itself at the answer,
tearing down whatever it was doing.

That question has no answer in general. A file of patterns can be included by
five songs or by none, so a library of snippets defeats it outright; and every
time it was asked, the render that was playing stopped and started again.

The song knows what it is made of. So the tab does the navigating: a song's
files are shown **in the song's own tab**, with a row above the text saying
which of them is in front and a menu of the rest.

There is no originating `.abydos/backlog` item: the backlog is retired and this
comes from a direct request.

## What Changes

- **A song's tab shows any of the song's files.** The text in front changes and
  the pane below does not — same render, same playback, same playhead. The tab
  keeps a code view per file, so going back to one is the caret, the folds, the
  scroll and the undo it was left with.
- **A row above the text: `♪ drive.song ⌄ › parts › bass.song`.** The song, a
  menu of every file it is made of with a tick on the one in front, and where
  in them the text below is. Nothing for a file that is not part of a song.
- **Opening one of a song's files navigates in that tab**, wherever the ask came
  from: the project tree, a jump to a definition, a driven step. No second tab,
  no second pane, nothing asked about which song anything belongs to.
- **⌘[ comes back.** Moving between a song's files is navigation and is recorded
  as such, so the history walks it like any other jump.
- **A jump that finds nothing says so.** A go-to-definition that lands nowhere
  used to do nothing at all, which cannot be told from a server with no jumps.

## Impact

- `EditorViewController.Tab`: `url` is the file being shown and `song` is what
  the tab is; the per-file half — document, code view, scroll view, server root,
  find state — moves in and out as the shown file changes.
- `EditorViewController+SongFiles` (new), `SongFilesBar` (new).
- `EditorViewController+Opening`: the per-file construction is its own function,
  so a tab can build another one; `open(fileURL:)` routes a song's file into the
  song's tab.
- `SongPreviewView`: `file` moves with the tab; the pane is not told anything
  else and does not restart.
- Everything that reads `tab.url` keeps meaning "the file in front", which is
  what all but a handful of its hundred-odd readers meant already.
