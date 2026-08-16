# 502. ⌃A, ⌃E and ⌃K do nothing: they send the paragraph selectors

0497 gave ⌃B and ⌃F their cases and left the rest of the emacs family alone,
because a keystroke nobody has asked about is a decision nobody has made. On
the way it pressed the rest of the family through the same driver, and the
answer is not the one you would guess from the selector names:

    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌃A          caret=50 selection=50..<50 “”
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌃E          caret=50 selection=50..<50 “”
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌃D          caret=50 selection=50..<50 “”
    EMACS: PROBE after ⌃D third ine of the file
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌃K          caret=50 selection=50..<50 “”
    EMACS: PROBE after ⌃K third ine of the file

**⌃D works** — the caret does not move, which is right, and the `l` at offset
50 is gone from `third line`. **⌃A, ⌃E and ⌃K do nothing at all**, and ⌃K
leaves the line exactly as ⌃D left it.

**With one caveat about ⌃D, and it matters.** The driver synthesises a
`keyDown` straight into the code view, which is the point — it proves the key
binding reaches the editor — but it skips the menu, and the menu is asked
first in the real app. `--menu-keys` says **Run ▸ Debug is ⌃D**. So ⌃D reaches
`deleteForward:` when nothing is in front of it, and in the app as shipped it
starts the debugger instead. Whether that is the right owner for ⌃D is a
question this item did not ask and should: it is the only emacs letter this
app has already spent on something else. ⌃A, ⌃E and ⌃K are unclaimed —
`--menu-keys` lists no menu item on any of them.

`CodeView.doCommand` handles `moveToBeginningOfLine:`, `moveToEndOfLine:` and
`deleteToEndOfLine:`, so reading the switch says these three should work. They
do not, because those are not the selectors those keys send. macOS's own table
is the answer —
`/System/Library/Frameworks/AppKit.framework/Resources/StandardKeyBinding.dict`:

    ^a  moveToBeginningOfParagraph:
    ^e  moveToEndOfParagraph:
    ^k  deleteToEndOfParagraph:
    ^d  deleteForward:              ← the one that is handled, and works

So this is the **paragraph** family and not the line family. 0495's audit
already listed `moveToBeginningOfParagraphAndModifySelection` and
`moveToEndOfParagraphAndModifySelection` as handled-neither-way, along with
`moveParagraphForwardAndModifySelection` and its backward twin, which are ⌃⌥↑
and ⌃⌥↓ and are dead for the same reason.

**Worth knowing before starting:** in a code editor a paragraph is not a
paragraph. Cocoa means "up to the next hard line break", which in a file of
source is a line — so `moveToBeginningOfParagraph:` can honestly go to the same
code as `moveToBeginningOfLine:` here, exactly as 0497 sent `moveForward:` to
the same code as `moveRight:`. That is the decision this item is really about,
and it wants writing down rather than aliasing quietly. What it is *not* is the
soft-wrap question: whether ⌃A on a wrapped row goes to the start of the row or
the start of the line is a separate answer, and `moveToLineEdge` already has
one that this item should not change by accident.

## ⌥↑ and ⌥↓ are half-working until this is done

Not a separate item, and the reason to take this one sooner than "somebody
eventually wants ⌃A". `StandardKeyBinding.dict` binds those two arrows to a
*pair* of selectors each:

    '~↑'   -> ['moveBackward:', 'moveToBeginningOfParagraph:']
    '~↓'   -> ['moveForward:', 'moveToEndOfParagraph:']

A list is sent in order, and an unhandled selector is skipped rather than
stopping the rest. Before 0497 both halves fell through and the keys were
dead; since 0497 the first half runs and the second does not, so ⌥↑ moves the
caret back **one character** and ⌥↓ forward one — a character-sized answer to
a paragraph-sized key. Watched, with 0497's driver and a probe taken out
again:

    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌥↑          caret=49 selection=49..<49 “”
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌥↓          caret=51 selection=51..<51 “”

Giving `moveToBeginningOfParagraph:` and `moveToEndOfParagraph:` their cases
completes both keys with nothing written for them specifically. The step back
is not a mistake in Cocoa's binding, either: it is what makes ⌥↑ go to the
*previous* paragraph when the caret is already at the start of one, so
whatever this item decides has to leave that working.

## Which keys these really are — the item above is wrong about two of them

Asked rather than believed, because the whole item turns on it:

    plutil -convert json -o - \
      /System/Library/Frameworks/AppKit.framework/Resources/StandardKeyBinding.dict

Every binding whose value mentions a paragraph, all nine of them:

    ^a     moveToBeginningOfParagraph:
    ^e     moveToEndOfParagraph:
    ^A     moveToBeginningOfParagraphAndModifySelection:      (⇧⌃A)
    ^E     moveToEndOfParagraphAndModifySelection:            (⇧⌃E)
    ^k     deleteToEndOfParagraph:
    ~↑     ['moveBackward:', 'moveToBeginningOfParagraph:']
    ~↓     ['moveForward:',  'moveToEndOfParagraph:']
    ~$↑    moveParagraphBackwardAndModifySelection:           (⌥⇧↑)
    ~$↓    moveParagraphForwardAndModifySelection:            (⌥⇧↓)

Two corrections to the item as filed:

- **`moveParagraphBackward:`/`moveParagraphForward:` are ⌥⇧↑ and ⌥⇧↓, not
  ⌃⌥↑ and ⌃⌥↓.** There is no `^~` binding in the dict except the word motions
  (`~^b`, `~^f` and their shifted twins) and the three writing-direction
  commands. ⌃⌥↑ and ⌃⌥↓ send nothing at all and are not a key this change can
  reach.
- **The bare `moveParagraphBackward:`/`moveParagraphForward:` are bound to no
  key whatsoever.** Only the `AndModifySelection:` twins have one — which is
  the reverse of the usual shape, where a base selector has a key and its twin
  is the same key with Shift. They are not merely unbound, either: **AppKit
  does not declare them.** `NSResponder.h` in the macOS 27 SDK has
  `moveParagraphForwardAndModifySelection:` and its backward twin at lines
  185–186 and no bare pair anywhere, which the compiler said before this item
  believed it — `cannot find 'moveParagraphBackward' in scope`. So the two
  selectors 0495's audit listed as missing from this switch are two methods
  that do not exist. Nothing can send them and no case can be written for
  them.

And the third thing, which is the argument for how the whole family has to
behave. ⌥⇧↑ is **not** ⌥↑ with Shift added. ⌥↑ is two selectors with a nudge
in front; ⌥⇧↑ is one selector and no nudge. The same key, one modifier apart,
composed two different ways — so `moveParagraphBackwardAndModifySelection:`
has to step to the previous paragraph *by itself* when the caret is already at
a boundary, because nothing is in front of it to do that, while
`moveToBeginningOfParagraph:` must *not*, because the nudge would then skip a
paragraph. Two selectors that sound like synonyms and are a deliberate pair.

That also settles the last of the item's three questions before any code is
written: **⌥⇧↑ and ⌥⇧↓ come along.** Leaving them out would give ⌥↑ and ⌥↓ a
shifted twin that does nothing, which is precisely the half-a-motion shape
0495 exists to stop, and this time the two halves are not even the same
selector.

## What a paragraph is here — decided

**A paragraph is one line of the file: the text between two hard line breaks.**
Not a blank-line-delimited block, not a soft-wrap row. That is what Cocoa means
by the word, and in a file of source it is a line, so all four of ⌃A, ⌃E, ⌥↑
and ⌥↓ are line-sized keys.

**But the motions are not `moveToLineEdge`, and that is the whole of the work.**
The item invites the alias — "it can honestly go to the same code as
`moveToBeginningOfLine:`, exactly as 0497 sent `moveForward:` to the same code
as `moveRight:`" — and the alias is wrong. `moveToLineEdge(start: true)` is not
"go to the start of the line"; `CodeView.swift:2321` is a **smart-home toggle**,
first press to the first non-blank and only a second press from exactly there to
column zero.

Put that behind ⌥↑, which AppKit sends as `moveBackward:` *then*
`moveToBeginningOfParagraph:`, and trace it with the caret at the first
non-blank of an indented line:

    caret at 74, the `f` of `    fourth line`
    moveBackward:                  → 73, inside the indentation
    toggle sees caret 73 ≠ 74      → back to 74

⌥↑ is dead, and it is dead only on indented lines: on an unindented one
`lineStart == indentEnd` and the toggle cannot tell the two presses apart, so
the alias hand-tests perfectly on a flat scratch file and fails in real source.
Measured, not reasoned — see "Watched with the naive answer" below, where the
run says `⌥↑ indent caret=74` from 74.

So the general rule, which is worth more than the four keys: **a selector that
AppKit sends as part of a sequence has to be a function of the position, not a
toggle over it.** The nudge in front of it feeds it a position nobody typed, and
anything that reads the caret to decide where to go is reading that synthetic
position as if it were intent. The smart-home stop is an affordance of the Home
*key*, which is pressed twice by a person who can see what happened the first
time; ⌥↑ presses it once, from a place one character to the left.

Two other things fall out of the same answer:

- **Emacs agrees.** `move-beginning-of-line` is column zero;
  `back-to-indentation` is the separate `M-m`. Somebody pressing ⌃A because
  their fingers know emacs wants column zero, and this now gives it — while
  ⌘← still gives them the smart stop, because ⌘← is the Home key.
- **Soft wrap does not come into it**, and no accident was needed to keep it
  out. A paragraph is bounded by hard breaks, so `moveToParagraphEdge` asks the
  rope for a *line* and never asks what row the caret is on.
  `moveToLineEdge`'s answer to the wrap question is untouched, which is what
  the item asked for.

**⌃K is the exception and shares the line code.** `deleteToLineEdge(start:
false)` already deletes from the caret to the hard end of the line and has no
toggle in it, so `deleteToEndOfParagraph:` can point straight at it. It stops
*at* the newline rather than taking it, so ⌃K at the end of a line is a no-op
and does not join the two — watched, below. That is the same answer as the
motions rather than a second decision: the break is the boundary of a
paragraph, not part of one. Emacs's `kill-line` does join, and this is not
emacs's `kill-line`; the selector macOS sends says `deleteToEndOfParagraph`,
which says where it stops.

## Who owns ⌃D — Run ▸ Debug keeps it

`--menu-keys`, run against this build, lists exactly two Control-only key
equivalents in the whole app:

    MENUKEY Run ▸ Run…: menu says ⌃R, pressed as ⌃R
    MENUKEY Run ▸ Debug: menu says ⌃D, pressed as ⌃D

⌃A, ⌃E, ⌃K and all four of ⌥↑, ⌥↓, ⌥⇧↑, ⌥⇧↓ appear nowhere in the report, so
nothing stands in front of the editor for any key this item touches. ⌃D is the
one that is spent, and it stays spent:

- **What ⌃D would gain is a duplicate; what Debug would lose is its only key.**
  `deleteForward:` is also ⌦, and on a keyboard without one it is fn-⌫. Run ▸
  Debug has ⌃D and nothing else — Run ▸ Go Debug (Delve) is a different command
  on ⌃⌘D. Trading a command's only binding for a second way to press a key that
  already has one is a bad trade in either direction you read it.
- **Nothing is broken by leaving it.** The `deleteForward:` case at
  `CodeView.swift:2159` is not dead code waiting for ⌃D; ⌦ reaches it every
  time. What the app loses is one emacs habit out of the eight this family has,
  and it loses it to a command somebody chose deliberately.
- **This item cannot make that trade honestly anyway.** Taking ⌃D back means
  finding Debug another key, and that is a decision about the Run menu made by
  somebody looking at the Run menu, not a side effect of a switch statement in
  the text view. Filing it would be legitimate; deciding it here would not.

So: **⌃A, ⌃E and ⌃K are the editor's, ⌃D is Run ▸ Debug's**, and that is now
written down rather than left as the accident of which menu was built first.

## Watched in the app

`--emacs-nav`, the driver 0497 built, with the paragraph family added to it and
pointed at a seven-line scratch file that has indented lines in it — 0497's
file was flat, and a flat file cannot tell the two candidate answers apart:

    0  first line of the file                   offsets  0–22
    1  second line of the file                          23–46
    2  third line of the file                           47–69
    3      fourth line, indented four spaces            70–107
    4          fifth line, indented eight              108–142
    5  sixth line, no indent at all                     143–171
    6  seventh and last line of the file                172–205

`2@6` is offset 53, the `l` of `line`; `3@4` is 74, the first non-blank of the
indented line; `3@11` is 81, in the middle of its text. The caret goes back
before every press, so each line is an independent keystroke.

**Before** — this build with the `doCommand` change taken out and rebuilt, not
remembered:

    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: ⌃A          caret=53 selection=53..<53 “”
    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: ⌃E          caret=53 selection=53..<53 “”
    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: ⇧⌃A         caret=53 selection=53..<53 “”
    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: ⇧⌃E         caret=53 selection=53..<53 “”
    EMACS: at 3@11     caret=81 selection=81..<81 “”
    EMACS: ⌃A          caret=81 selection=81..<81 “”
    EMACS: at 3@4      caret=74 selection=74..<74 “”
    EMACS: ⌃A          caret=74 selection=74..<74 “”
    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: ⌥↑          caret=52 selection=52..<52 “”
    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: ⌥↓          caret=54 selection=54..<54 “”
    EMACS: at 2@0      caret=47 selection=47..<47 “”
    EMACS: ⌥↑ at start caret=46 selection=46..<46 “”
    EMACS: at 2@end    caret=69 selection=69..<69 “”
    EMACS: ⌥↓ at end   caret=70 selection=70..<70 “”
    EMACS: at 3@4      caret=74 selection=74..<74 “”
    EMACS: ⌥↑ indent   caret=73 selection=73..<73 “”
    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: ⌥⇧↑         caret=53 selection=53..<53 “”
    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: ⌥⇧↓         caret=53 selection=53..<53 “”
    EMACS: at 2@0      caret=47 selection=47..<47 “”
    EMACS: ⌥⇧↑ start   caret=47 selection=47..<47 “”
    EMACS: line 2 is “third line of the file”
    EMACS: ⌃K          caret=53 selection=53..<53 “”
    EMACS: line 2 is “third line of the file”

Six dead keys — ⌃A, ⌃E, ⇧⌃A, ⇧⌃E, ⌥⇧↑, ⌥⇧↓ — and ⌃K leaving the line it was
pressed in exactly as it found it. **⌥↑ and ⌥↓ are the live regression**: 53 →
52 and 53 → 54, one character, on keys that should move a line. At the two
boundaries it is worse than merely small — ⌥↑ from the start of line 2 lands on
46, the newline at the end of line 1, and ⌥↑ from the first non-blank of the
indented line lands on 73, *inside the indentation*, which is not a place any
key should leave a caret.

**With the naive answer in place** — the paragraph selectors pointed straight
at `moveToLineEdge`/`deleteToLineEdge`, built and run, then thrown away:

    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: ⌃A          caret=47 selection=47..<47 “”
    EMACS: ⌃E          caret=69 selection=69..<69 “”
    EMACS: at 3@11     caret=81 selection=81..<81 “”
    EMACS: ⌃A          caret=74 selection=74..<74 “”      ← first non-blank
    EMACS: at 3@4      caret=74 selection=74..<74 “”
    EMACS: ⌃A          caret=70 selection=70..<70 “”      ← second press, column 0
    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: ⌥↑          caret=47 selection=47..<47 “”
    EMACS: at 2@0      caret=47 selection=47..<47 “”
    EMACS: ⌥↑ at start caret=23 selection=23..<23 “”
    EMACS: at 3@4      caret=74 selection=74..<74 “”
    EMACS: ⌥↑ indent   caret=74 selection=74..<74 “”      ← dead

Every line of that reads correct except the last one, which is the whole
argument in one number: 74 → 74. Nine keystrokes of evidence that the alias
works, and a tenth that says it does not.

**After:**

    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: ⌃A          caret=47 selection=47..<47 “”
    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: ⌃E          caret=69 selection=69..<69 “”
    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: ⇧⌃A         caret=47 selection=47..<53 “third ”
    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: ⇧⌃E         caret=69 selection=53..<69 “line of the file”
    EMACS: at 3@11     caret=81 selection=81..<81 “”
    EMACS: ⌃A          caret=70 selection=70..<70 “”
    EMACS: at 3@4      caret=74 selection=74..<74 “”
    EMACS: ⌃A          caret=70 selection=70..<70 “”
    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: ⌥↑          caret=47 selection=47..<47 “”
    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: ⌥↓          caret=69 selection=69..<69 “”
    EMACS: at 2@0      caret=47 selection=47..<47 “”
    EMACS: ⌥↑ at start caret=23 selection=23..<23 “”
    EMACS: at 2@end    caret=69 selection=69..<69 “”
    EMACS: ⌥↓ at end   caret=107 selection=107..<107 “”
    EMACS: at 3@4      caret=74 selection=74..<74 “”
    EMACS: ⌥↑ indent   caret=70 selection=70..<70 “”
    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: ⌥⇧↑         caret=47 selection=47..<53 “third ”
    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: ⌥⇧↓         caret=69 selection=53..<69 “line of the file”
    EMACS: at 2@0      caret=47 selection=47..<47 “”
    EMACS: ⌥⇧↑ start   caret=23 selection=23..<47 “second line of the file⏎”
                                 (the driver prints the real newline; ⏎ here)
    EMACS: at 2@6      caret=53 selection=53..<53 “”
    EMACS: line 2 is “third line of the file”
    EMACS: ⌃K          caret=53 selection=53..<53 “”
    EMACS: line 2 is “third ”
    EMACS: at 3@end    caret=91 selection=91..<91 “”
    EMACS: ⌃K          caret=91 selection=91..<91 “”
    EMACS: lines 3-4 are “    fourth line, indented four spaces”
                       / “        fifth line, indented eight”

Reading it as keys rather than numbers:

- **⌃A** goes to column zero on every line, indented or not — 81 → 70 and 74 →
  70 both, where the toggle gave 74 and 70.
- **⌃E** goes to the end of the line, 53 → 69.
- **⇧⌃A and ⇧⌃E** take the text with them, `third ` and `line of the file`.
- **⌥↑ and ⌥↓** are whole again: mid-line they go to the two ends of the line
  they are on (53 → 47, 53 → 69), and at a boundary the leading nudge does what
  it is there for — from the start of line 2 ⌥↑ goes to 23, the start of line 1,
  and from the end of line 2 ⌥↓ goes to 107, the end of line 3. **From the first
  non-blank of the indented line ⌥↑ goes to 70**, which is the case the naive
  answer killed.
- **⌥⇧↑ and ⌥⇧↓** select what the unshifted pair moves over, and at a boundary
  the single selector steps by itself: from 47 it takes 23..<47, the whole of
  line 1 and its newline. Press it again and it takes another line, which is
  what makes a run of ⌥⇧↑ select upwards.
- **⌃K** turns `third line of the file` into `third `. At the end of a line it
  takes nothing and lines 3 and 4 stay two lines.
- **⌃F, ⌃B, ⇧⌃F, ⇧⌃B, ⌃P, ⌃N** are byte-for-byte what the before run said —
  0497's keys are the control and this change did not touch them.

## Ruled out

- **Doing it inside 0497.** Its reported pair is `moveForward:`/`moveBackward:`
  — logical against visual order, one decision. This is a different family with
  a different question in it (what a paragraph means in code), and ⌃K deletes,
  which nothing in 0497 did. Bundling them would have made one item nobody
  could review.

## Found and ruled out on the way

- **The alias this item recommends, built and measured before it was
  rejected.** The item says the paragraph selectors "can honestly go to the
  same code as `moveToBeginningOfLine:`", and that is the one thing in here
  that is wrong in a way a reader cannot catch: `moveToLineEdge(start: true)`
  is a smart-home toggle, not a go-to-line-start, and a toggle inside a
  two-selector sequence makes ⌥↑ dead on indented lines and correct on flat
  ones. Written, built and run rather than argued away, because "this would be
  wrong" is a claim about a program. See "Watched with the naive answer" — one
  number, 74 → 74, against nine that look right.

- **A paragraph as a blank-line-delimited block.** Defensible in prose and
  wrong here, and it is ⌥↑ that says so rather than taste. ⌥↑ has to be
  `moveBackward:` then "the start of this block" and come out at the start of
  the *previous* block; with blocks, a caret anywhere in a five-line block goes
  to the top of it and the next press to the top of the block above — which is
  a fine key and is not the key macOS binds, because ⌥↓ paired with it would
  jump five lines where every other Cocoa app moves one. It would also make ⌃E
  and ⌃K wildly destructive in source: ⌃K would take the rest of a function.

- **⌃⌥↑ and ⌃⌥↓, which the item asks about, are not keys.** Neither is bound
  in `StandardKeyBinding.dict` to anything at all. The keys the item means are
  ⌥⇧↑ and ⌥⇧↓, and the methods it names — bare `moveParagraphForward:` and
  `moveParagraphBackward:` — are not declared by AppKit in the first place.
  Found by writing the two cases and being told `cannot find
  'moveParagraphBackward' in scope`, then confirmed in `NSResponder.h`.
  **0495's audit lists both of them as unhandled**, which is true and
  unfixable: two rows for methods that do not exist.

- **`deleteToBeginningOfParagraph:` is in, and nothing presses it.** The one
  paragraph selector AppKit declares that has no key in the standard dict. It
  is a case label pointing at `deleteToLineEdge(start: true)`, the function
  ⌘⌫ already uses, and leaving it out would have left the only half-handled
  pair in the family after this item. A user's own
  `~/Library/KeyBindings/DefaultKeyBinding.dict` can bind it.

- **No unit test, and it is 0495's and 0497's answer for the same structural
  reason.** `CodeView` lives in `AbydosApp`; the only test target is
  `AbydosKitTests`, and there is no `AbydosAppTests` to put one in. What could
  be tested without a window is a pure function from an offset and a rope to
  another offset — which is `Rope.lineByteRange`, already covered, plus two
  lines of arithmetic. What this item got wrong twice over is *what AppKit
  sends and in what order*, and no unit test in this repository can observe
  that. The before/naive/after driver runs are the check, and the naive run is
  the one that earned its keep.

- **⌃A does not agree with ⌘←, on purpose.** They are one key apart in the
  fingers and they now do different things on an indented line: ⌘← stops at
  the first non-blank, ⌃A goes to column zero. Not an oversight to tidy up
  later — ⌘← is the Home key and the two-press toggle is an affordance of
  being pressed twice by somebody watching, while ⌃A is emacs's
  `move-beginning-of-line`, which is column zero, and `back-to-indentation` is
  a separate binding in emacs too. The deciding argument is still ⌥↑ rather
  than either tradition: ⌃A and ⌥↑ share a selector, and only one behaviour
  makes both keys work.

- **⌥↑ was not merely small before this; at one boundary it was actively
  wrong.** From the first non-blank of `    fourth line` it left the caret at
  73 — *inside the indentation*, between two spaces. A key that moves one
  character is a key doing the wrong size of thing; a key that parks the caret
  in the middle of a run of indent looks broken. Worth recording because it is
  the strongest form of the "0497 half-completed these two keys" claim, and
  the item as filed had only the mid-line case.

- **The driver now edits the file it is pointed at, twice.** 0497 warned about
  this after ⌃D; ⌃K makes it permanent, since a run cannot show a deletion
  without doing one. The runs above go through a script that rewrites the
  scratch file first, and the second ⌃K's `at 3@end caret=91` is 107 − 16 —
  the first ⌃K's sixteen characters — rather than anything about ⌃K.

- **`--menu-keys` lists `Run ▸ Run…` on ⌃R and no second item on it**, though
  `AppDelegate.swift:2183-2196` adds two items with that key equivalent, `Run…`
  and `Run`. Only one reaches the report, and `MenuKeyReport.collect` filters
  nothing that would explain it. Not chased and not filed: it is a question
  about the Run menu, this item needed only to know which Control-only
  equivalents exist, and either reading of the ⌃R oddity leaves that answer
  the same two — ⌃R and ⌃D.

## Estimate

2026-08-16 14:07 — about twenty minutes left

## Steps

- [x] Ask `StandardKeyBinding.dict` which keys actually send the paragraph
      selectors, rather than taking this item's word for it

      Added while doing the work: the item says ⌃⌥↑/⌃⌥↓ and it is wrong, which
      changes what the fifth step below is about. See "Which keys these really
      are" — they are ⌥⇧↑ and ⌥⇧↓, and the way they are composed is the
      argument for how the rest of the family has to behave.
- [x] Decide what a paragraph is in this editor, and write the answer down

      One line of the file, between hard breaks — and *not* the same code as
      the line selectors, which is the part the item did not expect. See "What
      a paragraph is here".
- [x] Decide who owns ⌃D — Run ▸ Debug has it, and `deleteForward:` only gets
      it when no menu is in the way

      Run ▸ Debug keeps it. See "Who owns ⌃D".
- [x] `moveToBeginningOfParagraph:` and `moveToEndOfParagraph:` move the caret,
      and their `AndModifySelection:` twins take the selection with them
- [x] `deleteToEndOfParagraph:` deletes, so ⌃K does something
- [x] Decide about ⌃⌥↑ and ⌃⌥↓ — `moveParagraphForward:`/`moveParagraphBackward:`
      are the same family and unhandled, and either belong here or are said not to

      They are ⌥⇧↑ and ⌥⇧↓ and not ⌃⌥↑ and ⌃⌥↓, and they come along. The bare
      pair the step names does not exist in AppKit at all, so the only case
      that could be written is the `AndModifySelection:` one and it is written.
- [x] Watched from outside the app with `--emacs-nav`, which already knows the
      key codes for all of these letters

      Before and after, the before run made by taking the `doCommand` change
      out and rebuilding. A scratch file with indented lines in it, because a
      flat one cannot tell the two candidate answers apart.
- [x] Watched with the naive answer in place too, because the reason to reject
      it is a claim about the running program and not about the code

      Added while doing the work. See "What a paragraph is": aliasing the
      paragraph selectors onto `moveToLineEdge` kills ⌥↑ on an indented line
      and works everywhere else, so reading the diff would not have caught it.
- [x] `make test` and `make warnings` are clean

      2625 tests in 367 suites. One `PerformanceTests` case,
      `foldComputationIsReasonableOnHugeFile`, went over its 10 s bound at
      27.7 s with four other agents building beside it, and passes at 8.75 s
      run on its own with `FILTER`. `make warnings` reports no warnings in
      this repository's Swift, with the four vendored tree-sitter C ones it
      always reports.
- [x] Write down here what was ruled out on the way
- [x] `spec/editor.md` says what the project now does, beside what 0494, 0495
      and 0497 put there about the arrows

      Two `ADDED` and no `MODIFIED`, and the delta says why at length. The
      short of it: 0497's requirement is about a *character* and about which
      of two orders the editor has, which a line does not raise; 0494's and
      0495's are about the *edges of the file*, which nothing in this family
      reaches. The two new ones are separate from each other because one
      moves and one deletes, and the newline gets decided in the second.
