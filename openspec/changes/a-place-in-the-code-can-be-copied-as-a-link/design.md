## Context

Two strings, two audiences, and they fail in different ways.

`Sources/AbydosApp/Editor/CodeView.swift:2324` is what an assistant, a terminal
and `abydos` all understand. It costs nothing to make, needs no network and no
git, and it is wrong the moment somebody inserts a line above 2324. That is
acceptable for the use it is put to — a reference handed over now and acted on
now — and it is the reason it must stay readable.

`https://github.com/owner/name/blob/<sha>/path#L2324` is what a person opens.
It is right for ever, because a commit does not change, and it makes three
promises this app cannot keep on its own: that there is a remote, that the
commit is on it, and that the file on the forge is the file on screen. All three
can be checked here, and the checking is most of the work.

What exists: `GitForge` turns a remote into a `Repository` and builds branch and
commit pages from it. `GitRepository` knows the head commit and what is dirty.
`BreakpointAnchors` anchors a line by its text and its enclosing symbol and
re-finds it in a file that has been rewritten — built for breakpoints, and the
same problem word for word.

## Goals / Non-Goals

**Goals:**

- A place in the code can be copied as something an assistant can act on.
- A place in the code can be copied as something a person can open, pinned so
  that it stays right.
- A permalink that cannot be opened by its recipient says so before it is sent.
- A link this app is given lands on the line the text is on now, not the line
  the number used to mean.

**Non-Goals:**

- An `abydos://` scheme, and inbound URLs as commands.
- Anything that needs the network at the moment of copying. Whether a commit is
  on the remote is answered from the refs in this checkout.
- Pushing anything, ever, to make a link work.
- Forges beyond what `GitForge` already recognises.

## Decisions

**Two menu items, not one with a submenu.** "Copy Reference" and "Copy
Permalink" are different in kind, not in format: one is free and always
available, the other needs a repository with a remote and may have something to
say about it. A submenu hides the second behind a hover for no gain, and a
single item that picks for you is a menu item nobody trusts.

**The reference is repo-relative, not absolute.** An absolute path is right on
one machine and no other, and the audience for a reference is most often an
assistant working in this same checkout. A path relative to the project root is
what `abydos` resolves, what a stack trace looks like, and what survives being
pasted into a repository somebody else has cloned.

**A selection copies as a range** — `path:12-18` — because a person selecting
eight lines and getting the first one back has been given the wrong answer. The
caret alone copies `path:12`. Column is not copied: a column in a reference is
noise for every audience named here, and `abydos` accepts it but nobody reads
it.

**The permalink names the head commit, and says when the file is dirty.** Not
the last commit that touched the file, which sounds cleverer and is wrong: the
line numbers on the forge are the file as of the commit in the URL, and the
head commit is the one whose worktree somebody is looking at. If the file has
uncommitted changes, the line on the forge is a different line, and that is said
out loud at the moment of copying rather than left to be discovered.

**A commit not on the remote is a dead link, and is named as one.** Answered
from `git branch --contains` / the remote-tracking refs in this checkout — no
network, no `git fetch`, no push. The link is still copied: somebody may be
about to push, and refusing to copy would be this app deciding what happens
next. What it must not do is hand over a URL that 404s without a word.

**Re-finding happens when a link is opened, not when it is copied.** This is the
answer to the question the anchoring decision raised: an anchor in the copied
string would make `path:line` unreadable, which is the one thing it cannot be.
So the anchor is not carried — it is *recovered*. When this app is given a
permalink of its own whose commit is in this checkout, it reads the line as it
was at that commit, and finds where that text is now with `BreakpointAnchors`.
A `path:line` from anywhere is opened as it always has been, at the number, with
nothing invented.

**What it says when it moved.** A line that is re-found at a different number is
a fact worth one sentence — "line 2324 at 1c5f358 is line 2331 now" — and no
sentence at all when the number is unchanged, which is most of the time.

**Ruled out: an `abydos://` scheme.** It is the natural home for an anchor and
for opening a link by clicking it, and it was not chosen: it needs a URL type in
the bundle, a handler that treats an inbound URL as a command to open a file,
and a decision about what happens when the link names a project that is not
open. That is its own item, and neither string here needs it.

**Ruled out: putting the line's text in the reference.** `path:12 // return
titles.size()` survives an edit and is unusable everywhere the plain form is
used: it cannot be pasted into `abydos`, it wraps in a terminal, and half of it
is stale as soon as the line is edited rather than moved.

**Ruled out: a copy that pushes, or fetches, to make the link work.** Pushing is
somebody's decision and this app does not take it. Fetching at the moment of
copying makes a menu item that sometimes takes four seconds.

**Ruled out: teaching `Scripts/abydos` a new syntax.** It already opens
`path:line`, which is half of this. The other half is a URL, and a URL that goes
to a browser is the forge's business.

## Risks / Trade-offs

- **A permalink to an unpushed commit is the most likely mistake somebody can
  make with this.** → It is checked, and said, before the link leaves the app.
- **The dirty-file case is subtle**: the URL is not wrong, it points at a real
  line of a real commit; it is simply not the line on screen. → The sentence
  says which, rather than saying "uncommitted changes" and leaving the reader to
  work out what that means for their link.
- **Re-finding could put somebody somewhere they did not ask to be.** → It is
  bounded to the app's own permalinks with the commit in this checkout, and it
  always says when it moved the destination. Nothing is silent.
- **A monorepo where the project root is not the repository root** makes
  "repo-relative" ambiguous. → The reference is relative to the *project* root,
  which is what `abydos` resolves against; the permalink is relative to the
  repository root, which is what the forge serves. They can differ, and each is
  right for its own audience.

## Open Questions

- **Whether a keystroke is worth spending on the reference form.** ⌘⇧C is IDEA's
  "copy path" and is taken here by nothing, but a keystroke for a thing done
  twice a week is a keystroke not available for something done twice an hour.
- **What a permalink should do about a file that is not tracked by git at all.**
  Refusing is honest and unhelpful; there is nothing sensible to link to.
- **Whether the range form should be `#L12-L18`** (GitHub) or the forge's own
  spelling for every forge `GitForge` knows. GitLab and Bitbucket differ, and
  only GitHub's is certain without a machine to test against.
