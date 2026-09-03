## Context

`SidebarController` owns the git pages. Each opener — the log, the commit view,
a stash, the estate — begins with `leaveTerminalFullScreen()`, which un-maximises
the terminal panel when it has the whole window. That is not the same as
maximising the editor, which `git-pages` forbids; it is giving the editor back
the share it had, because while the panel is maximised `splitView.isHidden` is
true and a page opened into it is a page nobody can see.

`reopen(pages:)` restores what a project had open, by calling those same
openers. It runs on every project switch, and a project switch happens by
itself whenever the window is following its terminal and the shell walks into
another project — which is what switching a tmux window does.

## Goals / Non-Goals

**Goals:**

- A restored page comes back as a tab and takes nothing.
- A page somebody asks for behaves exactly as it does now.

**Non-Goals:**

- Changing what a project remembers, or whether pages are restored at all.
- Making a requested page open into a hidden editor. It has to take the window;
  that is what asking for it means.

## Decisions

**A parameter, not a flag on the controller.** `asked: Bool = true` on the four
openers, passed `false` by `reopen(page:)`. A `isRestoringPages` flag set around
the loop would have to survive the stash's own `Task` — the entries are listed
before the page can be made — and a flag that spans an await is a flag that is
wrong for whatever else runs in the gap.

**Defaulted to true, so every existing call is unchanged.** There are a dozen
callers between the sidebar's rows, the menus and the driver; the ones that
matter are the two that restore.

*Ruled out: not restoring pages while the terminal is maximised.* The pages are
part of what the project had open, and dropping them because of the panel's
height would be a second rule about somebody's arrangement, in the other
direction.

## Risks / Trade-offs

**A restored page opens into a hidden editor** → It does, and that is what
restoring means: it is a tab, in the group, where it was. It is on screen the
moment the editor is, and the two gestures that give the editor the window are
unchanged.
