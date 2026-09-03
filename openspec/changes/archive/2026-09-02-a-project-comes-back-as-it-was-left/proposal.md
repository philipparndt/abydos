## Why

Switching to another project and back loses two things somebody was in the
middle of: the git pages that were open — the commit page, the log page, a stash
page — and the commit message typed into the changes pane, summary and
description both.

Neither is an accident of one code path; both are the session's shape. The
session records the *files* that were open and deliberately drops pages:
`captureSession` filters `pageTitle == nil`, on the argument that "a path like
`/ideai/page/launch` is nothing to reopen" — true of the URL and not of the page,
which is a view with a repository, a scope and a selection behind it. And the
typed message is held nowhere but in two `NSTextField`s: it has never been
written down, so returning to the project rebuilds an empty pane.

The switch is not the only door onto the loss. Reading the repository finishes a
second or two after a window opens, and when it lands on a different work tree
the sidebar tool is rebuilt — the comment beside that code already names what it
costs: *"it took with it the commit message half typed into the pane and the
folders unfolded in it"*. What was true when that comment was written is still
true.

A commit message is the most expensive text in the app to lose: it is written
once, from a diff somebody has just read, and typing it again means reading the
diff again. Reported directly, 2026-09-01.

## What Changes

- The typed commit message — summary **and** description — survives leaving a
  project and coming back, and survives the sidebar being rebuilt underneath it
  when the repository finishes loading. It is per project, written where the
  rest of a project's session is written, and restored into whichever surface
  holds the message: the sidebar's changes pane or the commit page.
- The git pages that were open come back open: the commit page, the log page
  with its ref and file scope, and the stash page on the stash it was showing.
  Pages whose identity is the identifier alone — the estate overview, launch
  configurations, settings — come back the same way.
- A page is reopened only once the repository is ready, because every opener
  refuses while `project.git` is still nil, which would silently drop the
  restore.
- Nothing is restored into a project that never had it: a project switched to
  for the first time opens as it does today.

## Capabilities

### Modified Capabilities

- `sessions`: added requirements — the pages a window had are part of a
  project's session, and the message being composed is too.
- `git-pages`: an added requirement — a page reopened by a session comes back on
  what it was showing, not merely open.

### New Capabilities

<!-- none: this is the session's own account, widened. -->

## Impact

- **AbydosKit**: `ProjectSession` gains two optional, additive fields — the
  composed message and the open pages — with `SessionStore` reading and writing
  them the way `reviewTicks` and `breakpoints` already are; absent means
  nothing, so an older session file still reads.
- **AbydosApp**: `ChangesPane` gains a real getter and setter for the pair of
  fields (only a summary-only test setter exists today, and the private
  `subjectField` and `bodyView` are the whole of it); `EditorViewController`'s
  capture stops dropping pages and learns to describe one; `SidebarController`
  reopens them through the openers it already has; `MainWindowController`
  captures on the way out and restores on the way in, including after
  `readGit()` rebuilds a tool.
- **Driver**: a switch-and-return step, so the claim is read off a run rather
  than argued: type a message, switch away, switch back, report the fields and
  the tabs.
