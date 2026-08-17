# 528. The unfocused selection is too faint to see in the editor

> the focus works now, but the disabled selection highlight is too dimmed and is
> almost invisible

Reported with a screenshot of a selected line in `Package.swift` with the
keyboard elsewhere: the band is there, and you have to look for it.

## The numbers, in the scheme this was seen in

    editorBackground   dark  #151210
    selectionInactive  dark  #2A2018   ← what an unfocused selection uses
    selectionBackground dark #4A2C0E   ← what a focused one uses
    selectionActive    dark  #6B3B10   ← what a focused *row* uses

`#2A2018` against `#151210` is a handful of points of lift. It reads as a band
on a list row, which is a short strip with a boundary on both sides; it does not
read behind a run of code, which is what the editor draws.

The other two schemes are no different in kind — `blue` has `#343842`, `dracula`
`#343746`, both against their own dark backgrounds.

## This was predicted, and the prediction was passed on and not taken

0510 gave both views one rule, `Theme.selection(_:hasKeyboard:)`, and used the
scheme's own `selectionInactive` for the unfocused case in all three places.
The agent that read the ground before that work said, in as many words, that
`selectionInactive` "is tuned as a list-row band, not as a run of text behind
code". That was forwarded to the agent doing the work, which chose it anyway —
reasonably, since it avoided adding a scheme key and the tree had used it for
years. The reporter has now seen what the difference is.

So this is not a mistake to undo. `Theme.selection` is the right shape and one
rule for both views is the right idea; what is wrong is that **a row and a run
of text want different amounts of lift from the same background**, which is
exactly the distinction `SelectionKind` already carries.

## Worth deciding

- **A fourth scheme key, or a derivation.** `selectionBackgroundInactive` beside
  the other three is the obvious answer and costs a key in `Scheme.swift`, all
  three scheme files, and a decision in `SchemeLibrary`'s grouping about how it
  is derived for a scheme that omits it. Deriving it instead — a blend of
  `selectionBackground` toward the background, or `selectionInactive` lifted —
  costs nothing to the schemes but decides for everybody.
- **How much lift is enough.** This is judged by eye against a real file, in
  each of the three schemes and in both light and dark. A number chosen in one
  scheme and applied to the others is how the three end up disagreeing.
- **Whether the list is faint too.** The reporter named the editor. The same
  colour is used for a checklist row and a tree row, where it has been for
  years and nobody has complained — which is evidence that the row case is
  fine, not that it is.

## Steps

- [ ] Decide between a scheme key and a derivation, and write down why
- [ ] An unfocused selection in the editor is visibly a selection, in all three
      schemes, light and dark
- [ ] A focused selection is unchanged, and the two are still tellable apart
- [ ] The list and the tree are looked at, and either left alone deliberately or
      changed with them
- [ ] Screenshots of before and after, in at least two schemes, since this is
      judged by eye
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says what the project now does, if the requirement 0510
      added needs it
