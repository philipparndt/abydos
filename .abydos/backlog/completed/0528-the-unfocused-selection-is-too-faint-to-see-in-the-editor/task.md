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

## Decided: a fourth key, which a scheme may leave out

**Both, and the split is not a compromise.** The key carries the taste; the
derivation carries the schemes that have not got one.

**Why not a derivation on its own.** The obvious derivation is
`selectionBackground` blended toward `editorBackground` — the focused selection,
damped. It cannot work, and the reason is arithmetic rather than taste: a blend
toward the ground is *bounded above* by the focused colour's own lift, and in
the light halves the focused colour has less lift than what is drawn today.
Contrast against `editorBackground`, measured:

    scheme          focused   unfocused today
    abydos dark      1.47        1.17   ← the report
    abydos light     1.22        1.27
    blue dark        1.70        1.45
    blue light       1.37        1.28
    dracula dark     1.56        1.21
    dracula light    1.49        1.25

Every damping constant that fixes `abydos dark` makes `abydos light` *fainter
than it is now*, because 1.22 is the ceiling there and 1.27 is the floor. The
other derivation — `selectionInactive` pushed away from the ground by a factor
— has no ceiling, and overshoots for the same reason: at the factor `abydos
dark` needs (1.17 → ~1.4) `blue dark` reaches 2.0, louder than its own focused
selection at 1.70, so an unfocused selection would shout over a focused one.
One constant cannot serve six situations whose starting points range from 1.17
to 1.45 and whose ceilings range from 1.22 to 1.70. Those six are what a
derivation would have to be right about, and they are not alike.

**Why the key may be left out.** `Scheme.readApp` walks `SchemeRole.allCases`
and refuses a file missing any of them — deliberately, and `Schemes/README.md`
has a section arguing for it. Adding a required role would therefore refuse
every scheme anybody has already written, on the grounds that it was written
before this morning. So this one role is optional, which is a documented
derivation rather than a silent default: absent, it is the midpoint of
`selectionInactive` and `selectionBackground`. That is bounded by construction
— never louder than the louder of the two it sits between — and it is a
sentence a scheme author can hold in their head: *halfway between the gray band
and the real selection.*

**And the three shipped schemes state it**, six values chosen by eye, one
scheme at a time. Which is the last argument for a key: the value is judged
against a real file in a real palette, and a scheme JSON is a resource rather
than code, so trying one is a re-bundle rather than a recompile.

## The six values, and what each was judged against

`selectionBackgroundInactive`, with the contrast each has against its own
`editorBackground` and, beside it, the focused selection it must stay under:

    scheme          before   after   focused
    abydos dark     #2A2018  #3A2E24  #4A2C0E     1.17 → 1.42, under 1.47
    abydos light    #E9E0CF  #E5D9C2  #F6E3BC     1.27 → 1.35, over 1.22 ✱
    blue dark       #343842  #383C46  #2C4269     1.45 → 1.54, under 1.70
    blue light      #E1E3E8  #D9DBE1  #CBDEFB     1.28 → 1.38, over 1.37 ✱
    dracula dark    #343746  #404149  #44475A     1.21 → 1.40, under 1.56
    dracula light   #E4E2D5  #DAD8C8  #CFCFDE     1.25 → 1.38, under 1.49

✱ In the light halves an unfocused selection carrying *more* lift than a focused
one is not a mistake and is what macOS itself does: the focused colour is a pale
tint and the quiet one a gray, and they are told apart by hue rather than by
weight. Which is the other half of every value here — each is pulled toward
neutral, so beside the focused colour it reads as *the colour drained out of it*
rather than as a darker version of it. `abydos dark` is the clearest case: amber
`#4A2C0E` against warm gray `#3A2E24`.

**Dracula was the one that had to be looked at twice.** Its focused selection is
`#44475A`, a blue-gray rather than a hue, so the first value chosen by contrast
alone — `#3E4153`, 1.41 — was the right weight and the wrong colour: two blue
grays eleven points apart, and the pictures showed them as the same band. It is
`#404149` instead, the same weight with the blue taken out, so the pair separates
the way the other two schemes' pairs do.

## The list and the tree are left alone, deliberately

Unchanged, and not by omission: `Theme.selection(.row, hasKeyboard: false)` is
still `selectionInactive`. `images/rows-left-alone-abydos-dark.png` is why — a
selected results row and a selected tree row, both with the keyboard in the
editor, both plainly there. A row is a strip the width of the pane with an edge
above and below; it is legible at a lift that vanishes behind code, which is the
whole of what this item found. Years of nobody complaining is weak evidence on
its own, and the picture is the strong kind.

Two of the numbers make the same point from the other side. The tree's band has
*less* raw lift than the editor's had — `#2A2018` on the sidebar's `#1C1712` is
fourteen points of red, against twenty-one on the editor's `#151210` — and it is
the one that reads. So this was never "the unfocused colour is too dark"; it was
the shape it is asked to fill.

## Ruled out on the way

- **A derivation instead of a key.** Both of them, with the arithmetic above:
  blending the focused colour toward the ground is capped below what is drawn
  today in two of the six cases, and lifting `selectionInactive` away from the
  ground overshoots `blue dark` past its own focused selection. Six situations,
  no constant that suits them.
- **Making the new role required, like every other.** It would have refused
  every scheme in anybody's `~/.config/abydos/schemes` for having been written
  before today. `Schemes/README.md` argues for refusing a file that is missing a
  colour, and that argument is about a *forgotten* key — it is not an argument
  for breaking files that were complete when they were written.
- **Drawing the unfocused selection as the focused one at reduced alpha.**
  Tempting, because it would compose over the current-line band for free, and
  wrong for the same reason as the blend: alpha over the ground *is* the blend,
  bounded by the focused colour, and it cannot reach the lift the light schemes
  already have.
- **One quiet colour for the whole window, kept.** That is what 0510 decided and
  it survives as a *rule* — one function, `hasKeyboard` and nothing else — while
  the colours it returns are now four. The alternative reading of "one colour"
  is what this item is fixing.
- **Changing the row case with the editor.** Considered and refused; see above.
- **A photograph of a real project.** Every picture here is a throwaway package
  in the session scratchpad, which is the rule this project learned in 0522.

## Two notes for whoever reads this next

**The before pictures came out of the same binary as the after ones**, with the
new key pointed at each scheme's `selectionInactive` — which is exactly what the
old code drew. That was checked rather than assumed: the re-rendered abydos-dark
shot differs from a capture taken with the pre-change binary in one rectangle,
`(1920, 1247)–(2189, 1269)`, which is the language-server line in the status bar,
and nowhere else.

**`--select-lines` leaves the editor without the keyboard**, which is what it was
written for. To photograph the *focused* selection with the same geometry, put
`--click-below` in front of it: it fires at 2.5s and reports "no empty space
below the text", and it makes the `CodeView` first responder all the same —
`SELECT … keyboard=CodeView` instead of `keyboard=NSWindow`.

## The pictures

All six schemes were looked at, light and dark; three pairs are kept here.

- `images/editor-before-abydos-dark.png` and `…-after-…` — the reported case,
  seven lines of `Package.swift` selected with the keyboard in the terminal.
- `images/editor-before-dracula-dark.png` and `…-after-…` — the second dark
  scheme, and the one whose value was chosen twice.
- `images/editor-before-blue-light.png` and `…-after-…` — a light scheme, where
  the change is small on purpose.
- `images/editor-focused-abydos-dark.png` — the same selection with the keyboard
  in the editor, which is what the quiet colour has to stay tellable apart from.
- `images/rows-left-alone-abydos-dark.png` — a results row and a tree row, both
  unfocused, both unchanged.

## Estimate

2026-08-17 10:15 — done, bar the push

## Steps

- [x] Decide between a scheme key and a derivation, and write down why
- [x] An unfocused selection in the editor is visibly a selection, in all three
      schemes, light and dark
- [x] A focused selection is unchanged, and the two are still tellable apart
- [x] The list and the tree are looked at, and either left alone deliberately or
      changed with them
- [x] Screenshots of before and after, in at least two schemes, since this is
      judged by eye
- [x] A scheme that leaves the new key out still loads, and gets a colour —
      added once it was clear that a required role would refuse every scheme
      anybody already keeps
- [x] `make test` and `make warnings` are clean
- [x] Write down here what was ruled out on the way
- [x] `spec/editor.md` says what the project now does, if the requirement 0510
      added needs it
