## Context

Two strips, the same shape, neither bounded:

    PanelTabStrip.recomputeLayout()      EditorTabBar.recomputeFrames()
      var x: CGFloat = 0                   var x: CGFloat = 0
      for item in items { … x += width }   for item in items { … x += width }

Neither implements `scrollWheel`. Both then place their trailing controls
backwards from `bounds.width`, so the tabs and the controls occupy the same
pixels and are both drawn: the panel's session tag is a pill at 14% alpha with a
tab's name legible through it.

They differ where it does not help. An editor tab is `min(260, max(90, raw))`; a
panel tab is `max(96, raw)` with **no ceiling**, plus room reserved for a badge
whether or not there is one, so a shell in a deep directory can take a third of
the strip on its own. And every panel tab is called `Local` until somebody renames
it, which is what makes the reported case so bad: sixteen tabs, indistinguishable,
and six of them past the edge.

`selectNextTab` is `editor.selectNextTab` — ⌘] and ⌘[ move between *editor* tabs.
The panel has no equivalent, so a terminal past the edge is reachable by widening
the window or closing the ones in front of it.

The immediate overlap is already fixed in the working tree: the trailing controls
draw on an opaque ground, the answer `EditorTabBar.drawPreviewControl` gave for
itself. That is the right fix for the drawing and it sharpens this one — a tab
that used to show through the session tag now does not show at all.

`--tab-fill <n>` was added while looking at the overlap and is how any of this is
driven. Twelve tabs was previously twelve clicks by hand, which is why no
screenshot in the repository ever showed a full strip.

## Goals / Non-Goals

**Goals:**

- Every open tab is reachable with the pointer, whatever the width of the window.
- The tab that is active is one that can be seen.
- One answer to "which of these are hidden", used by both strips, so they cannot
  drift into two behaviours.
- Discoverable without documentation: the count says there is something there.

**Non-Goals:**

- A tab switcher over everything open, ⌘⇧O-shaped. That is a different feature
  with a different gesture, and it would put the tab somebody is looking at into a
  menu of things they cannot see.
- Keyboard cycling for panel tabs. Worth having and worth arguing separately —
  ⌘] belongs to the editor and taking it for whichever strip has focus is a
  decision about the whole window's key handling.
- Closing tabs from the menu. Reaching a tab is the fault; the menu is not the
  place to grow the tab's own context menu.
- Reordering, grouping or hiding tabs by rule.

## Decisions

**A menu, not a scrollbar, for reaching what is hidden.** Weighed:

- *Shrink the tabs until they fit.* Ruled out on this strip's own numbers: the
  floor is 96 points and the reported case is sixteen tabs, which needs 1536 —
  and shrinking below the floor turns sixteen tabs named `Local` into sixteen
  slivers named nothing. Shrinking makes the thing it is meant to fix worse in
  exactly the case that was reported.
- *A scrolling strip with a visible scroller.* A scroller on a strip 30 points
  tall is a scroller nobody aims at, and the wheel over a tab bar is a gesture
  people discover by accident when they meant to scroll the terminal underneath.
- *A chevron with a menu.* Chosen. The shape is in this window twice already —
  the `+`'s chevron on this very strip, the play button's on the run control —
  and its comment there is this decision in advance: *"the button does the
  ordinary thing, and the chevron beside it opens the ways of doing it that are
  wanted now and then."*

**The count is on the chevron.** `⌄ 6` rather than `⌄`. Three hidden and eleven
hidden are different situations, and the number is the only thing that says which
without opening the menu. It is also what makes the control discoverable at all:
a bare chevron beside four other glyphs is one more glyph.

**Hidden means covered, not off the end.** The trailing controls now paint over
the strip, so the honest question is not "does this frame exceed `bounds.width`"
but "is any of it under the controls". A tab half under the session tag is not a
target — it is a tab somebody will click and miss. So the measurement takes the
leading edge of the trailing controls, which both strips already compute, and a
frame is visible only if it is wholly in front of it.

**The active tab is kept visible, and that means an offset.** Selecting a hidden
tab from a menu and having it stay hidden is the same fault with a click in front
of it. Without moving anything there is no way to show it, so the strip gains one
piece of state: where the run of tabs starts.

It changes for one reason only — the active tab does not fit — and it changes by
the least that makes it fit. **Not a scroll position:** nothing scrolls it, the
wheel does not touch it, and it is not remembered anywhere. This is the smallest
mechanism that keeps the promise, and the wheel can be hung off it later by
whoever wants it.

The consequence is stated rather than hidden: with an offset, tabs can be off the
*leading* end too, so the menu lists both and the count includes both. A strip
scrolled to the last tab with fifteen in front of it says `⌄ 15`.

**Which tab the offset is measured from survives a reload.** The panel's strip is
rebuilt whenever the tmux mirror re-reads, which is several times a second while
a session is being watched — so the offset is held as the identity of the tab it
starts at, not as an index. An index survives nothing: tmux moves windows, and a
tab closed in another client shifts every number after it.

**One measurement, two strips.** The two `recomputeLayout` implementations stay
separate — they measure tabs differently on purpose — and what they share is the
part that does not differ: given frames, a leading edge and a trailing edge, which
are visible. A small type in `AbydosKit` with tests, since it is arithmetic and
needs no window.

**Cost.** This runs where layout already runs — when the item set changes, not per
frame and not per scroll. It is one pass over frames that have just been computed.
The menu is built when it is opened.

## Risks / Trade-offs

- **An offset is a scroll position by another name, and will be asked to behave
  like one.** → It changes for one reason and is documented as that. If the wheel
  is added later it inherits a tested measurement rather than inventing a second.
- **Tabs hidden at the leading end are a new thing to be confused by.** Nothing
  is hidden there today because nothing ever moves. → The count covers both ends
  and the menu is in tab order, so the ones before the visible run come first and
  read as "further back".
- **The tmux strip mirrors somebody else's window list.** An offset held across a
  reload can point at a tab that has gone. → Held by identity, and a missing
  identity means the offset is dropped, which puts the strip back at the start —
  the state it is in today.
- **Two chevrons on the panel strip**: the `+`'s and the overflow's. → They are at
  opposite ends and mean different things, but it is worth looking at once the
  strip is full before deciding the overflow one needs a different mark.
- **A menu of sixteen entries all called `Local`.** → The menu entry carries what
  the tab cannot: the working directory, or the command. That may be the most
  useful part of this change for the reported case, and it is the part with no
  precedent to copy.

## Open Questions

- Does the overflow chevron sit inside the trailing controls' opaque ground, or
  in front of it with its own? Inside is tidier; in front makes the count part of
  the tab strip rather than part of the panel's controls.
- Should a menu entry show the shell's directory for a `Local` tab, and if so how
  much of it? Sixteen identical names is the reported case, so this decides
  whether the menu answers it.
- Does the editor strip want the count too, or only the chevron? It has ⌘] and
  ⌘[, so its case is milder.
- `--tab-fill` prints a pane count; should it print the hidden count as well, so
  a driven run can assert on it rather than on a picture?
