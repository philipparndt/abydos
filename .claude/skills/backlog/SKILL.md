---
name: backlog
description: Work the backlog-spec backlog in .abydos/backlog — file an item, pick up a ready one in a worktree of its own, and keep the spec in .abydos/backlog/spec true as part of the work. Use whenever asked to file, pick up, start, implement or finish a backlog item, to say what is left to do, or to change what the spec says.
---

# The backlog

backlog-spec keeps everything left to do in `.abydos/backlog/`, as
files: the state of an item is the folder it is in, and its history is
`git log`.

**Read `.abydos/backlog/AGENTS.md` before touching any of it.** It is one
page and it is the whole of the workflow — how an item is shaped, how the
global spec under `.abydos/backlog/spec/` is kept true as part of doing
the work, and the order to pick up a `ready/` item in.

The four things worth knowing before you get there:

- `abydos-backlog next` is how you find something to do. Only `ready/`
  counts; `open/` is a pile.
- Work happens in a worktree of its own, which `abydos-backlog start
  <number>` makes for you.
- Every item carries a `## Steps` checklist, and it is how anybody else
  can tell what is done and what is still missing. Tick a `[ ]` to `[x]`
  in the same commit that finishes it, never ahead, and add steps you
  find rather than doing unlisted work.
- An item that changes behaviour is not finished until the spec says so.
  `abydos-backlog done <number>` does that fold and will tell you what
  would not go.
