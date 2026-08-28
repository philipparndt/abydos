## 1. The message moves under the diff

- [x] 1.1 In `ChangesPane.arrangePage`, the split's right-hand side becomes a
      vertical stack of the diff and the message. The left-hand side stays the
      two file lists and runs the page's full height.
- [x] 1.2 The constraints follow: the split is pinned on all four sides, and the
      message's own leading, trailing and bottom are the diff column's rather
      than the page's. The insets stay what they are.
- [x] 1.3 Check the divider still places itself once, in `layout()`, and that
      dragging it moves the message with the diff. That rule is not this
      change's to touch.

## 2. The description collapses

- [x] 2.1 A chevron beside the summary, on the leading edge, so it reads as
      belonging to the field it opens — the Draft button is on the other end and
      the two must not collide.
- [x] 2.2 The 150-point height constraint becomes one that can be turned off, and
      collapsing hides the view rather than removing it: `NSStackView` collapses
      a hidden arranged subview, and the text has to survive being put away.
- [x] 2.3 Collapsed at build, and the state kept for as long as the page is open.
      A page opened afresh starts collapsed.
- [x] 2.4 The chevron's direction says which way it goes, and its tooltip says
      what it does.

## 3. The gestures that open it

- [x] 3.1 Return at the end of the summary opens the description and puts the
      keyboard in it. `NSTextField`'s delegate already sees the key — the field
      is the pane's own delegate, which is where the summary is read from now.
- [x] 3.2 The commit button carried **plain Return**, not ⌘Return as this change
      first assumed, so taking Return for the description would have left the
      page with no keyboard commit at all. Both it and Push — which swap `\r`
      between them — now carry ⌘Return, and the spec says so instead of claiming
      nothing changed.
- [x] 3.3 A draft that comes back with a description opens it; one with only a
      summary leaves it alone.

## 4. Driving it, and finishing

- [x] 4.1 A driven-run verb that opens the commit page in a repository with a
      staged change and says what the layout came to: whether the description is
      showing, and the heights the diff and the message ended up with. The
      numbers are the claim — "the diff has the height the box would have taken"
      is not something a screenshot can be diffed against.
- [x] 4.2 Drive it against a copy under the scratchpad, with a throwaway bundle
      id and an unpinned UUID, and a defaults domain of its own: a short page
      with the description collapsed, the same page with it open, and the summary
      Return that opens it. Never `make install`, and never against a real
      checkout — this page has `Commit` and `Push` buttons on it.
- [x] 4.3 A screenshot of the short page, since the fault was reported as one and
      the numbers alone will not show that it reads better.
- [x] 4.4 `make test` and `make warnings`, both clean, and their exit codes read
      rather than their output skimmed. `ChangesPane` is on the file-size list; if
      it grows past its recorded length, raise the number in
      `Scripts/file-size-allowed.txt` in the same commit, which is what that
      list's own rule asks for.

## What this makes untrue

`openspec/specs/git-pages/spec.md` says the commit page has "what to do with the
set along the bottom", which after this is along the bottom *of the diff*. That
requirement is modified in `specs/git-pages/spec.md` rather than added to, since
the sentence it changes is already written there.

`openspec/specs/commit-message-drafts/spec.md` says a draft fills both fields.
That stays true and gains a sentence: it also shows the one it filled.

Nothing else. The sidebar arrangement, what may be amended, and when Push lights
up are untouched.
