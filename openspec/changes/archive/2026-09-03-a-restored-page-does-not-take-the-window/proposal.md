## Why

Reported: the maximised terminal is lost when switching tmux tabs — and, once
narrowed down, "when one project contains a log view or git commit view, the
terminal is minimized when switching to this pane".

The chain is the whole explanation. Switching a tmux window moves the shell;
while the window is following its terminal that switches the project; a project
switch restores what that project had open, which includes its pages; and every
page opener begins with `leaveTerminalFullScreen()`. So a project remembering a
log or a commit page hands the window back from the terminal on arrival — with
nobody having asked to look at anything.

The rule those openers carry is right for the gesture they were written for.
The editor is *hidden* while the terminal has the window, not merely small, so a
page somebody asks for has to take the window or it opens where it cannot be
seen. A page being *restored* asked for nothing.

`git-pages` already says neither page may maximise the editor, for the same
reason in the other direction: "the panel's height is the person's own
arrangement, and rearranging it to show them a commit is" not the page's call.
Restoring one is even less its call.

## What Changes

- **A page opener knows whether it was asked for.** `showLogPage`,
  `showCommitPage`, `showStashPage` and `showEstatePage` take `asked`, true by
  default, and only give the editor the window when it is true.
- **Restoring a session's pages passes `asked: false`.** They come back as tabs,
  where they were, behind whatever has the window.
- Nothing changes for a page somebody opens: the sidebar's rows, the menu and
  the review page all still take the window, because they were asked to.

## Capabilities

### Modified Capabilities

- `git-pages`: says that a page being restored does not take the window from
  the terminal, alongside the requirement that opening one does not maximise
  the editor.

## Impact

- **AbydosApp**: four signatures in `SidebarController` gain a defaulted
  parameter; `reopen(page:)` passes it.
- **Driven**: a run that maximises the panel and switches project restores a
  log page and stays maximised.
