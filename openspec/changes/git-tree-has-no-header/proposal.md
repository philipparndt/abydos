# The git tree has no header

## Why

The header above the git tree costs **58 points** — an 8-point inset, a 22-point
search field, a half-inset, a 20-point button row, a half-inset — in a pane 300
points wide whose whole job is a list. A row of that tree is 24 points, so the
chrome is two and a half rows of branches nobody can see.

What it buys is poor:

- **The filter holds a permanent row for an occasional job**, and it is the
  *second* branch filter in the window. The branch pill opens
  `ProjectSwitcherPopover` in its branches mode, which lists branches, groups
  them by folder and filters them — better than this field does, one click away,
  and reached from the titlebar rather than from a pane that has to be open.
- **`New Branch…` is a full bezel** for something done a few times a day.
- **Commit is not there at all.** The most frequent act in the pane has no
  visible affordance: it is in the context menu of the working copy row, which
  has to be guessed at. It is also called `Commit…`, which reads as *commit now,
  after a confirmation* — it opens the commit view, where hunks are chosen and a
  message written, and nothing is committed by pressing it.

The rule that fixes this is already written in this repository, as the comment
explaining why the traffic button exists:

> The repository, as a control. It reads `↓3 ↑1` and it is also the button:
> fetch when level, pull when behind, push when ahead. That is where fetch and
> pull have been missing from — **a verb here hangs off the row that draws its
> object, and nothing drew the repository.**

`git-refs-tree` already says the same thing about folders: *a folder row SHALL
carry the verbs that make sense for a set of branches*. The header exists
because two objects had no row — the repository, and (for the purposes of a
verb) the working copy, which has a row but no verb on it.

Give the repository a row and there is nothing left for a header to do.

There is no originating `.abydos/backlog` item; the backlog was retired before
this was raised.

## What changes

**The header goes.** No filter field, no `New Branch…` button, no traffic
button. The pane is one outline from its top edge, which is what
`git-refs-tree` already says it is.

**The repository becomes the first row**, and carries what the traffic button
carried: the project, the branch it is on, and how far it is from its upstream,
said in words — `3 behind · 1 ahead` — with the verb that follows from that
state. It is the same fetch-or-pull-or-push control, drawn as the object it acts
on rather than as a button floating above one.

**That row stays put while the tree scrolls.** This is the one thing the header
was doing that a row does not do for free, and it is the reason the traffic
button was in the header: how far you are from the remote is state, and state
that scrolls out of sight is state nobody reads.

**The working copy row gets its verb**, shown whenever there is anything to
commit, reading `Review 1 change…` — named after what is done next rather than
after the outcome. `⇧⌘K` and the context menu keep working and say the same
words.

**`LOCAL` gets a `+`** for a new branch, which is the rule `git-refs-tree`
already states about folder rows applied to a section row.

**The filter moves to `⌘F`**, opening over the list the way the editor's find
bar does, closing on `esc` and when emptied. Filtering behaves exactly as it
does today once open — flattening the tree, which is already spec'd.

## Capabilities

### Modified Capabilities
- `git-refs-tree`: the outline gains a repository row that does not scroll, the
  working copy and `LOCAL` rows gain verbs, and the filter becomes a find bar
  rather than a permanent field.

## Impact

- `BranchesPane.build()` loses `filterField`, `newButton` and `trafficButton`
  and the constraints that place them; `refreshTraffic` moves onto the row.
- A row action affordance is built once rather than wired per button — the
  repository row, the working copy row and `LOCAL` all use it, and stash and
  remote rows can later.
- **Row actions need a keyboard equivalent or they are a mouse-only feature**,
  which these panes were just fixed not to be. The selected row's action fires
  on a key; `⏎` already checks a branch out, so the two have to be told apart.
- `git-remote-traffic` is untouched: what fetch, pull and push do, and the pull
  dialog, are the same. Only where the control is drawn changes.
- The pane keeps its context menus unchanged, so nothing that is discoverable
  today stops being discoverable.
