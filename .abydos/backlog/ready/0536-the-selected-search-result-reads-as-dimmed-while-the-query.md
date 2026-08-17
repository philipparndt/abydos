# 536. The selected search result reads as dimmed while the query field has the keyboard

> the highlighted item in the search is actually dimmed instead of highlighted.
> This leads to confusion what it the active item.

## This is the design working, not a regression

Worth establishing first, because three things merged today touch this area and
none of them is the cause. 0529 made search preview as the selection moves, 0533
rewrote the reveal, 0528 changed the selection colours — and the reveal path
still passes `focusEditor: false`, `activate(index:focusEditor:)` honours it
(0523's comment explains at length why), and `Theme.selection(.row, …)` returns
`selectionActive` for a focused row exactly as before.

What is happening is `spec/search.md:201`:

> A list that has not got the keyboard says so: a selected row is drawn in the
> strong highlight only while the list has it, and in the unfocused gray once it
> has not.

And the ordinary way to use search puts the keyboard in the **query field**:
type a query, results arrive, `ResultChecklist` selects row 0 by itself. So at
the moment the results appear — the moment somebody is looking hardest at them —
the selection is at its lowest contrast, and the row's *text* dims with it
(`ChecklistCell` asks `isSelected && hasKeyboard`). Band and text together is
why the report says "actually dimmed" rather than "not highlighted enough".

The numbers, dark `abydos`, against `sidebarBackground` `#1C1712`:

    selectionActive    #6B3B10   what a focused row gets
    selectionInactive  #2A2018   what this row gets

## Why 0528 did not already fix this

0528 fixed exactly this complaint for the **editor** and left the row case alone
*deliberately*, with an argument written into the item: the tree band has less
raw lift than the editor's had — 14 points of red against 21 — and is the one
that reads, "so it was never the colour, it was the shape". A short strip with a
boundary either side reads at contrast a run of text does not.

**That argument was made about the project tree, and a results row is not one.**
A results row is wide, full of text, and stacked against its neighbours — much
closer to the run of text 0528 *did* fix than to the sidebar band it measured. So
this is not 0528 being wrong; it is 0528's own reasoning applied to a row it did
not look at.

## The question that decides the fix

**Was the keyboard in the query field, or in the list?** The two readings want
different work and the first step is to establish which:

- **In the field** (much the likelier, and what the description implies): the
  list is behaving as specified and the *specification* is what is wrong. See
  below.
- **In the list**: then `hasKeyboard` is answering wrongly somewhere and this is
  a straightforward bug. Note `ResultChecklist.hasKeyboard` requires
  `responder === tableView` while `ChecklistRowView.hasKeyboard` also accepts a
  descendant — two definitions of one thing, which is worth reconciling either
  way.

## Worth deciding, if it is the field

- **Whether the field and the list are one control.** ↓ from the field moves the
  keyboard into the results, so while typing, the list genuinely is inert — but
  nobody experiences it that way. They are one pane doing one job, and a query
  field with a live result list under it is the case where "this list is not
  listening" is true and unhelpful. The change would be that a results list
  draws its selection as active while the keyboard is anywhere in *its own
  pane*, including the field. That is a spec change to `search.md`, and
  `usages.md` should then say why the usages list — which has no field — is not
  affected.
- **Or lift the row's unfocused colour**, the way 0528 lifted the text's. This
  keeps the "unfocused says so" rule and only argues about how much lift. It also
  changes the *project tree*, which nobody has complained about, and 0528's
  measurement says the tree is fine — so this option has to say what it does
  about that. A fifth scheme key for a row, beside 0528's fourth for text, is
  where this ends up.
- **Or both, with different jobs**: active-while-the-pane-has-it for the results
  list, and a lifted unfocused colour for when the whole panel really is inert.
- **The dimmed text is a separate lever.** Even at low band contrast, keeping the
  row's text at full strength would leave the selection legible. Whether text
  should dim at all is worth asking on its own — it is the half that makes this
  read as "dimmed" rather than "unhighlighted".

## Steps

- [ ] Establish which state the reporter was in, reproduced rather than assumed
- [ ] If the keyboard was in the list, `hasKeyboard` is fixed and the two
      definitions of it are reconciled
- [ ] Typing a query and looking at the results makes plain which row is active
- [ ] Whatever is decided, the project tree and the usages list are looked at
      too, and either left alone deliberately or changed with it
- [ ] Screenshots before and after, in at least two schemes, light and dark —
      this is judged by eye
- [ ] `spec/search.md` says the new rule and `spec/usages.md` agrees or says why
      it differs
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
