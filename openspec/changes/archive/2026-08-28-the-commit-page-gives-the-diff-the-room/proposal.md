# The commit page gives the diff the room

## Why

The commit page spends a fixed 224 points on its message area whatever height it
has, and lays it across the whole width. Both are in `arrangePage`, and both can
be read off the constraints: the summary field is 26 points, the description box
is pinned at `body.heightAnchor.constraint(equalToConstant: 150)`, the commit row
is about 20, and there are two 6-point gaps and 16 points of inset around them.

That is the whole of the page on a short one. The capture this was reported from
shows the diff reduced to four lines — one hunk header, two context lines and the
pair being changed — under a description box that is empty, and above a commit
row. The thing the page exists to let somebody read has less room than the empty
box below it.

The width is the other half. The message spans from the left edge to the right,
so it sits under the file lists as well as under the diff — and the file lists
have nothing to do with the message. They lose height to it for no reason, in a
page where the list of what changed is the other thing worth seeing.

The description box is empty in that capture, and it is empty most of the time:
the sidebar already keeps the one-line case, and this page is reached *because*
somebody wants the diff or a longer message. Reserving a paragraph's worth of
height for the message that has not been written yet, against the diff that has,
is the wrong way round.

## What Changes

- **The message area moves under the diff**, into the right-hand side of the
  split. The file lists run the full height of the page, and dragging the
  divider moves the message with the diff it belongs to.
- **The description collapses behind a chevron** beside the summary, and starts
  collapsed. Expanded, it is the box it is today; collapsed, it costs one row of
  chrome instead of 150 points of empty field.
- **The chevron remembers** for as long as the page is open, so somebody who
  writes long messages opens it once rather than once per commit. A fresh page
  starts collapsed.
- **Return at the end of the summary opens it**, because pressing Return there is
  what somebody does when they mean to keep writing. The commit is ⌘Return, as it
  already is.
- **A draft that comes back with a description opens it.** Collapsing text that
  has just been written would hide work — and the draft is the one moment the
  description is full without anybody having typed in it.

## Capabilities

### New Capabilities
*(none — this is the commit page behaving better, not a new thing it does.)*

### Modified Capabilities
- `git-pages`: the commit page's layout. What the page's spec calls "what to do
  with the set along the bottom" becomes along the bottom *of the diff*, and the
  description gains a collapsed state and the chevron that opens it.
- `commit-message-drafts`: a draft that fills the description opens it, so what
  it wrote is on screen rather than behind a chevron.

## Impact

- `ChangesPane.arrangePage` is where all of it is: the split gains a vertical
  stack on its right-hand side, and the constraint that pins the description to
  150 points becomes one that can be turned off.
- The sidebar arrangement is untouched. It has its own path through `build`, its
  own 70-point box and the `…` that promotes what is typed to the page, and none
  of that changes.
- `ClaudeDraft`'s side is one line: what it already fills, it now also reveals.
- No new dependency, no change to what a commit is or how one is made. `Commit`,
  `Push`, `Amend` and their enabling rules are as they were.
