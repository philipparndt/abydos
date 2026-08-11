# 470. Usages in the bottom panel, as a job somebody works through

Find Usages answers into `UsagesPanel`, a floating `NSPanel` added as a child
window over the code, 760×520 in the middle of the window, with a **Dock** button
that moves it into the *sidebar*. Reported:

> The usages view shall be opened in the bottom view, it should support multi
> selection and manual deletion for progress tracking, it should not only jump to
> the usage on a click but also on keyboard navigation

Which is four things, and three of them already exist one pane away.

## Most of this is `SearchPane`, and that is the point

`SearchPane` is 942 lines of exactly this job — a list of places in files that
somebody opens one at a time, decides about, and moves past. It already has
multi-selection (`allowsMultipleSelection = true`), a per-row done state carried
on the row rather than computed while drawing, file headings that count how many
of their matches are done, a `✓` toggle that hides what is finished, undo, and a
`keyDown` hook on the table.

**So this item is mostly moving usages into the bottom panel and reusing that,
not writing it again.** Where the two lists differ is real but small: a usage
comes from the language server rather than from a text search, so its rows are
`LSPLocation` and its heading is "N usages in M files" rather than a query. If a
common list is the right answer, say so and build it; if the honest thing is a
second pane that shares the checklist and not the view, say that instead. What
must not happen is a third copy of the done logic.

## The word "deletion" is worth one paragraph before anybody writes code

The report says *manual deletion*. `SearchPane`'s doc comment argues at length
for the opposite word, and the argument is good enough that it should be answered
rather than ignored:

> The word is **done**, never "delete", "remove" or "clear". "Mark as Done" and
> "Mark as Not Done" cannot be read as touching the disk, which "Dismiss" —
> halfway between putting a thing aside and getting rid of it — can. […] The key
> is **␣**, which is what ticks a checkbox everywhere in the system, is
> destructive nowhere, and is nowhere near ⌫. ⌫ and ⌘⌫ are deliberately left
> unanswered here: a key that trashes files one pane over must do nothing at all
> in this one.

⌘⌫ in the project tree moves a file to the trash, and both panes are the same
list-shaped thing full of file names. It also argues for keeping the row —
struck through, greyed, in place — because a list that removes rows as they are
ticked moves everything under the pointer on every press, so the next keystroke
lands on something nobody has looked at.

**That reasoning applies here unchanged, so the default should be ␣ and "done".**
But the report asked for deletion, and there is a case for it that search does not
have: usages are transient — nobody comes back to a usage list tomorrow — so
"gone" may genuinely be what somebody wants, and the `✓` toggle already gives
the shortening list without the risk. Decide it, write down which and why, and if
it does become a removal then it needs a keystroke that is *not* ⌫ and a heading
that still says how many there were.

## Opening on keyboard navigation has a cost worth naming

`SearchPane` opens on `table.action` and `doubleAction` — a click, not a
selection change. Opening as the selection moves is the right feature and is what
the report asks for, but held ↓ through two hundred usages would open two hundred
files, and this app keeps a tab per opened file. The usual answer is a transient
or preview tab that is replaced by the next one rather than accumulating, and
whether this app has such a thing — and what it does to the tab bar, to `didOpen`
traffic at the language server, and to the undo stack — is the design question in
this item. Measure the `didOpen`/`didClose` traffic before deciding; the server
is told about every one of them.

Two smaller decisions that follow from it: whether the editor takes focus when a
row opens it (it must not, or the next ↓ goes to the code and the job stops), and
whether a click and a keystroke should differ at all.

## The floating window stays; the default turns around

Both arrangements are wanted, and only the default is wrong. Added to the report
after the first pass:

> maybe I also like the current docked variant, but it should started docked and
> support then the expand to window

So `UsagesPanel.show(locations:over:)` building a child window and putting it in
the middle of the screen is what changes: **usages arrive docked**, and there is a
way from there to a window for somebody who wants one big enough to read. The
`Dock` button becomes its inverse and the flow runs the other way.

Which means the machinery is not thrown away — `onDock` already hands a content
view across to `MainWindowController`, and a view that can move once can move
twice. Two things it does not answer and somebody should:

- **A window that has been expanded, then dismissed — what does the next Find
  Usages do?** Coming back docked when somebody has just chosen a window is an
  answer that will not be believed; remembering the choice means remembering it
  somewhere, and per project is a different feeling from per session.
- **Docked *where*.** The report says the bottom view, and `onDock` today goes to
  the **sidebar** — so "the current docked variant" and "the bottom view" are two
  different places, and this item cannot keep both without becoming three ways to
  show one list. Take the bottom panel, beside search, since that is where the
  checklist this reuses already lives, and say in the item what became of the
  sidebar route.

## Steps

- [ ] Decide whether this is one list shared with search or a pane sharing its
      checklist, and say why
- [ ] Usages open in the bottom panel, beside search
- [ ] Multi-selection, and the done state — with the word and the key decided
      against `SearchPane`'s argument rather than around it
- [ ] Opening as the selection moves, without accumulating a tab per usage and
      without the editor stealing focus
- [ ] Usages arrive docked, with a way from there to a window — the flow the
      `Dock` button runs today, turned around
- [ ] Decide what the next Find Usages does after somebody has expanded one, and
      where that choice is remembered
- [ ] Say what becomes of the sidebar dock, since the report's "bottom view" and
      today's docked variant are two different places
- [ ] Watch somebody work through a real usage list — the 263-location one from
      0469 is a good size
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does
