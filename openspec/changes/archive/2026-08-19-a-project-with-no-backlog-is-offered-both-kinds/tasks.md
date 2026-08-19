## 1. One button, one implementation

- [x] 1.1 Move `NoticeButton` out of `FileNoticeView.swift` into a file of its
      own, unchanged in appearance, and leave a line in `FileNoticeView` saying
      where it went and why it is not private any more.
- [x] 1.2 `make warnings` clean after the move, which is what catches an
      access level left behind.

## 2. The command OpenSpec is set up by

- [x] 2.1 `OpenSpec.initCommand()` beside the archive and apply commands it
      already spells, so the string `openspec init` exists in one place rather
      than in a view.
- [x] 2.2 A test that the command is what somebody would type, next to the
      existing ones in `OpenSpecChangeTests`.
- [x] 2.3 Whether the CLI is there is `OpenSpec.commandLine()`, which is the
      login-shell search — not a fixed list of directories, which on this
      machine finds nothing.

## 3. The view

- [x] 3.1 `BacklogAbsentView` drawn as `FileNoticeView` is: an icon, a title,
      one line of reason, a row of buttons, centred.
- [x] 3.2 Two buttons — making a backlog, and setting up OpenSpec — with the
      terminal command for each under them.
- [x] 3.3 The OpenSpec button is disabled where `openspec` is not installed, and
      says `OpenSpec.installHint` instead of the command line.
- [x] 3.4 `applySettings()` keeps up: fonts, colours and the icon come from the
      theme, and this view is rebuilt or restyled on a zoom change like the
      others.
- [x] 3.5 The title stops being `<project> has no backlog`, which is now only
      half of what it is saying.

## 4. What the buttons do

- [x] 4.1 The backlog button keeps `confirmMakeBacklog()` and its sheet exactly
      as they are.
- [x] 4.2 The OpenSpec button opens a terminal in the project and runs
      `openspec init` in it, through the same path that starts an agent in a
      pane — not a background process, because the command asks questions.
- [x] 4.3 Once an `openspec/` exists the pane shows the board without being
      reopened: the watcher cannot report a directory it was never able to
      watch, so this is the same re-read `makeBacklog` does.

## 5. Tests as claims

- [x] 5.1 What can be decided without a window: the command line, and that the
      absence of the CLI is answerable. In `AbydosKitTests`, since the view is
      in the app target and the suite cannot reach it.
- [x] 5.2 A driver verb that reports what the empty state offers — the title,
      each button, whether it is enabled, and the line under it — so that the
      four states (neither, no CLI, backlog made, openspec made) can be read
      rather than photographed.

## 6. Watched

- [x] 6.1 Against a scratchpad copy, never a real checkout: a project with
      neither, photographed, beside the editor's file notice for the same
      window — the two should look like one design.
- [x] 6.2 The OpenSpec button, driven, with the terminal's own output read
      afterwards: `openspec init` running and waiting for its answer.
- [x] 6.3 The same run with `openspec` hidden from the search, which must say
      the install hint and refuse rather than open an empty terminal.

## 7. Finish

- [x] 7.1 `.abydos/backlog/spec/backlog.md` says what the pane offers a project
      with none. It says "offers to make one"; that sentence is what this makes
      untrue, and it becomes both offers.
- [x] 7.2 `make test` and `make warnings`, both clean, exit codes trusted.
- [x] 7.3 Write down what was ruled out: `--tools all`, `--tools none`, a sheet
      of our own for OpenSpec's assistants, and a shared empty-state component.
