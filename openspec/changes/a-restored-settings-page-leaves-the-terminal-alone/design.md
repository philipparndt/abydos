## Context

`showSettingsPage` in `MainWindowController+Running.swift` is four lines: leave
the terminal's full screen, find the group, find or make the `SettingsPage`,
open it. The first line is right for a page that is about to appear behind a
terminal that has the whole window — a page nobody can see — and it is what a
file from the tree, a breakpoint hit and a compare page do for the same reason.
It runs every time the method does, and the method does not ask whether the
page is already open. `group.openPage` with an identifier that is already in
the group brings that page forward and opens nothing; the terminal has been
un-maximised in front of it all the same.

The report: *"when settings is open in one workspace and switching back to
this, the terminal is minimized. This should only happen when settings is
initially opened and not when it is just restored."*

## What was measured, 2026-09-10

**Reactivating the window does not move the panel.** A driven run opened the
settings page first, maximised the terminal at three seconds (`PANEL:
maximized=true`), sent the app behind the Finder at six and brought it back at
eight, and read the layout at the end by pinning a preview tab, which changes
nothing else: `panelMaximized=true`. `windowDidBecomeKey` runs on that return
and touches the tree, the editor's files and git, none of which reach
`leaveTerminalFullScreen`. Whatever "switching back" is, it is not the window
becoming key.

**Opening the page again is certain, by reading.** ⌘, (`AppDelegate.showSettings`
→ `showSettingsPage`) and the gear on the sessions bar (`bar.openSettingsPage`)
both run the four lines whether or not the page is open. A settings page left
open, a terminal maximised over it, and ⌘, pressed to get back to the page:
the terminal is un-maximised, the page comes forward, and nothing was opened.
That is the report's shape — the page was open, it was restored, the terminal
went — and it is the path this change closes. If the maintainer's gesture is a
macOS Space switch instead, the driver cannot make one, and the first task
asks.

**The eight callers of `leaveTerminalFullScreen`**, read for the same fault:
a file from the tree with focus, an archive entry pinned, open as hex, a
finding or a checklist row from the panel, a debugger stop, a compare, and the
review pane's `openPage`. All but the last open something new each time; the
review pane's opens a page by identifier the way settings does, and gets the
same rule.

## Decisions

**Opening a page that is already open is not an opening.** `showSettingsPage`
asks the group for the page first, and leaves full screen only when it has to
make one. The review pane's `openPage` does the same. A page that exists is
brought forward exactly as `openPage` already brings it, and the terminal is
where the reader left it.

*Ruled out: never leaving full screen for the settings page.* The first time is
right — a page opened behind a full-window terminal is a page nobody can see,
and asking somebody to find the maximise button to read the settings they just
asked for is the trap this line was written against.

*Ruled out: leaving full screen only when the page will be visible after the
open.* That is the same rule said the long way: a page already in the group is
visible after the open exactly when it was visible before.

**A driving step that opens the settings again**, `--settings-again <seconds>`,
so the claim is two `PANEL` lines: maximised before, maximised after.

## The real cause, 2026-09-10

The ⌘, path above is real and fixed, but it is not what the maintainer hit. The
report is: a window with Follow Terminal on, two tmux windows in two different
projects, the terminal maximised on window 1 with the settings page open;
switching to window 2 and back un-maximises it, every time, about a second
after the switch.

The second is the tell. Following the terminal switches project, and switching
project restores the new project's open pages — `SidebarController.reopen(page:)`.
Its comment already names this bug for the commit and log pages: *"a window
following its terminal switches project when the shell walks into another one …
Reported as the maximised terminal being lost on a tab switch."* The commit,
log, stash and estate pages were given an `asked` flag — `if asked {
leaveTerminalFullScreen() }` — so a page **restored** with a project (asked:
false) does not give the editor the window. The **settings** page was the one
case that never got the flag: `reopen(page:)` called `openSettingsPage()`, which
left the terminal's full screen unconditionally. So a project that had the
settings page open lost its maximise on every follow.

**The fix.** `showSettingsPage` gains `asked`, and leaves full screen only when
asked and the page is not already there. `reopen(page:)` restores it with
`asked: false`, the way it restores the other four. The maximise is global
window state and a follow now leaves it alone.

Driven with `--restore-pages settings`, whose report says the maximise before
and after and which tabs opened:

| Restore of the settings page | maximised before | after | tabs |
| --- | --- | --- | --- |
| the old path (`asked: true`) | yes | **no** | Settings |
| the fix (`asked: false`) | yes | yes | Settings |

The settings tab opens either way; only the maximise differs, which is the
whole of the report.

## What the fix measured, 2026-09-10

`--settings-again 6` on a scratch project, the panel maximised at three:

| Run | before the second ⌘, | after |
| --- | --- | --- |
| before the fix, page already open | maximised | **not maximised** |
| after the fix, page already open | maximised | maximised |
| after the fix, no page yet | maximised | not maximised — the first opening, as it should |

## Release note

> **Getting back to the settings page leaves the terminal alone.** Opening the
> settings still gives the editor the window when the terminal had all of it —
> a page nobody can see is no use — but pressing ⌘, to return to a page that
> is already open no longer does; the terminal stays as it was.

## Asked of the reporter

- Is "switching back" ⌘, or the gear, a macOS Space, or another window of
  this app? — *A **tmux window switch**, the maintainer, 2026-09-10, with the
  exact steps: a tmux window 1 with the settings page open, a tmux window 2
  without, the terminal maximised on window 1, switch to window 2, switch back
  to window 1 — and it is no longer maximised, every time. Not ⌘, and not the
  macOS window, which the first fix and the first measurement covered. The app
  notices tmux's active window return to one whose editor holds the settings
  page, and un-maximises. A different path, reopened below.

## Open Questions

None beyond the question above.
