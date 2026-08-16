# 497. ⌃B and ⌃F do nothing while ⌃P and ⌃N work

macOS has carried the emacs motions since NeXT, and they work in every standard
text view — TextEdit, Mail, Notes, Xcode, any `NSTextField`. ⌃B goes back a
character, ⌃F forward one, ⌃P up a line, ⌃N down one. Here the vertical half
works and the horizontal half does nothing at all.

`NSResponder.h:152-155` is the whole of why:

    - (void)moveForward:(id)sender;    // ⌃F
    - (void)moveRight:(id)sender;      // →
    - (void)moveBackward:(id)sender;   // ⌃B
    - (void)moveLeft:(id)sender;       // ←

Four methods, not two. `moveForward:` is not `moveRight:` — the pair is
*logical* order against *visual* order, and they part company in right-to-left
text. `CodeView.doCommand` answers to the visual pair and not the logical one,
so ⌃B and ⌃F fall through `default:` and are dropped. ⌃P and ⌃N survive because
AppKit sends them as plain `moveUp:` and `moveDown:`, which are handled; there
is no separate logical selector vertically for them to fall through.

**This is not a gap 0495's audit missed.** That one paired every
`…AndModifySelection:` with its base and found every row yes/yes or no/no. Both
halves of this pair are unhandled, so its rows were honest — a whole motion is
absent rather than half of one, which is a different question and this is it.

Found while answering "what do ⌃B and ⌃F usually do", after 0495 recorded them
in passing.

## Worth deciding — decided

**The two selectors share a case, and the reason is not the one this item
expected.** `moveForward:` goes to the same code as `moveRight:`, and
`moveBackward:` to the same as `moveLeft:`. What the item guessed would be a
concession — aliasing logical order onto visual order and hoping RTL never
turns up — is the wrong way round once you read what the code on the other end
of `moveRight:` actually does:

    private func moveHorizontally(_ delta: Int, extending: Bool) {
        …
        var offset = caret + delta

`caret + delta` is an offset into the document. That is **logical order
already**. There is no visual-order motion in this editor to alias anything
onto: `moveRight:` has been pointed at the logical one since it was written,
and in right-to-left text it is → that goes the wrong way, both before this
change and after it. ⌃F is the selector that is *correctly* named for what
these four cases do.

So the decision, said out loud as the item asked: **this editor has one
horizontal motion and it is the logical one.** ⌃F and → both step one character
forward through the document; ⌃B and ← both step one back. In an RTL line that
makes ⌃F right and → wrong, and → is exactly as wrong as it was yesterday.

Three things checked rather than assumed before writing that:

- **Nothing in this editor does bidi.** `git ls-files '*.swift' | xargs grep -l`
  for `bidi`, `rightToLeft`, `WritingDirection`, `kCTRunStatus` matches **no
  Swift file in the repository**. The one place the two orders could differ is
  drawing — a line goes to `CTLineCreateWithAttributedString`
  (`CodeView.swift:648`), and CoreText reorders bidi runs when it lays one out
  — so an RTL line would be *drawn* reordered while every offset around it
  stayed logical. That is a pre-existing gap between what is drawn and what the
  arrows do, it is what RTL support would have to close, and it is not this
  item.
- **The same switch has paired the same two orders for as long as it has had
  word motion.** `moveWordLeft:`/`moveWordBackward:` share a case and
  `moveWordRight:`/`moveWordForward:` share the other one
  (`CodeView.swift:2125`). ⌥← and ⌥→ have therefore always answered to both
  orders. Doing anything else for the character pair would have made the two
  neighbouring pairs disagree about a question neither of them can answer.
- **The pairing is not a guess about what ⌃F sends.** macOS says so:
  `/System/Library/Frameworks/AppKit.framework/Resources/StandardKeyBinding.dict`
  binds `^f` → `moveForward:`, `^b` → `moveBackward:`, `^F` →
  `moveForwardAndModifySelection:`, `^B` → `moveBackwardAndModifySelection:`.

**Four selectors, not two.** The `AndModifySelection:` twins are in, in the
same commit as the bare pair. 0495's audit already recorded both rows as
no/no — a whole motion missing rather than half of one — and doing the bare
pair alone would have converted it into exactly the half-a-motion shape 0495
exists to stop.

**The rest of the emacs family stays out, and is now filed rather than
guessed at.** See "The rest of the family" below: ⌃D already works, and ⌃A, ⌃E
and ⌃K are dead for a different reason than this item's, which is why they are
0498 and not more lines here.

## Watched in the app

`--emacs-nav`, a driver of its own beside `--word-nav` and `--vertical-nav`,
against a seven-line scratch file of ordinary short lines — 0494's file has a
723-character first line, which is what a *vertical* driver needs and is in the
way here. Line 2 is `third line of the file` and starts at offset 44, so `2@6`
is offset 50 and the character there is the `l` of `line`. The caret is put
back before every press, so each line is an independent keystroke and not a
run.

**Before**, with the same driver and the `doCommand` change stashed out of the
working tree and the app rebuilt — not remembered, and not read off the
diff:

    $ build/Abydos.app/Contents/MacOS/Abydos --open …/emacs --file …/emacs.txt --emacs-nav

    EMACS: word wrap is on
    EMACS: the file ends sixth lines / seventh and last line of the file
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌃F          caret=50 selection=50..<50 “”
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌃B          caret=50 selection=50..<50 “”
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⇧⌃F         caret=50 selection=50..<50 “”
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⇧⌃B         caret=50 selection=50..<50 “”
    EMACS: at 2@0      caret=44 selection=44..<44 “”
    EMACS: ⌃B          caret=44 selection=44..<44 “”
    EMACS: at 0@0      caret=0 selection=0..<0 “”
    EMACS: ⌃B          caret=0 selection=0..<0 “”
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌃P          caret=26 selection=26..<26 “”
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌃N          caret=73 selection=73..<73 “”

Every press of the four is the line above it, character for character, which
is what this driver prints when a keystroke does nothing at all. ⌃P and ⌃N are
the control and they work: 50 → 26 is column 6 of the line above, 50 → 73
column 6 of the line below. The report at the top of this item, watched.

**After:**

    EMACS: word wrap is on
    EMACS: the file ends sixth lines / seventh and last line of the file
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌃F          caret=51 selection=51..<51 “”
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌃B          caret=49 selection=49..<49 “”
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⇧⌃F         caret=51 selection=50..<51 “l”
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⇧⌃B         caret=49 selection=49..<50 “ ”
    EMACS: at 2@0      caret=44 selection=44..<44 “”
    EMACS: ⌃B          caret=43 selection=43..<43 “”
    EMACS: at 0@0      caret=0 selection=0..<0 “”
    EMACS: ⌃B          caret=0 selection=0..<0 “”
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌃P          caret=26 selection=26..<26 “”
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌃N          caret=73 selection=73..<73 “”

One character each way, and Shift decides only whether the character comes with
it: ⇧⌃F takes the `l` at 50, ⇧⌃B the space at 49. ⌃P and ⌃N are unchanged from
the before run, which is the point of having them in it.

**The two edges.** At `2@0` — offset 44, the very start of line 2 — ⌃B lands on
43, which is the newline that ended line 1, so the caret is at the end of the
line above. That is a step over a character that happens not to be printable
and not a case in the code, and it is what every other text view on this
machine does. At offset 0 there is nothing behind the caret and the clamp in
`moveHorizontally` keeps it there: 0 → 0, the one place where these keys still
look dead and are not.

**Soft wrap was on and it does not matter.** `moveHorizontally` is `caret ±
1` and never asks what row it is on, so there is nothing for wrapping to
change — unlike the vertical keys 0494 had to run twice. The run says which
mode it is in anyway, because the setting persists between launches and has
already been read as the wrong one of the two twice. The run itself shows no
line wrapped: ⌃P and ⌃N land on column 6 of the neighbouring *lines*.

## The rest of the family — pressed once, then filed as 0498

The item says ⌃A, ⌃E, ⌃D and ⌃K are their own decisions, and they are. What
they are not is a guess: the driver was given a probe with all four in it, run
once, and the probe taken out again — the same move 0494 made with ⌘⇧↑ and 0495
made with the wrap comparison.

    EMACS: ⌃A          caret=50 selection=50..<50 “”
    EMACS: ⌃E          caret=50 selection=50..<50 “”
    EMACS: ⌃D          caret=50 selection=50..<50 “”
    EMACS: PROBE after ⌃D third ine of the file
    EMACS: ⌃K          caret=50 selection=50..<50 “”
    EMACS: PROBE after ⌃K third ine of the file

**⌃D already works** — the caret staying at 50 is right for a forward delete,
and the `l` of `third line` is gone. **⌃A, ⌃E and ⌃K do nothing**, and reading
the switch would have said the opposite: `moveToBeginningOfLine:`,
`moveToEndOfLine:` and `deleteToEndOfLine:` all have cases. They are not the
selectors those keys send. `StandardKeyBinding.dict` binds `^a`, `^e` and `^k`
to the **paragraph** selectors, which have no case — the same six rows 0495's
audit listed as handled in neither form.

That is a different bug from this one with a real question inside it (what a
paragraph is in a file of source), so it is **0498** in `open/`, and four
keystrokes stayed out of this item.

## Ruled out

- **Anything that touches ⌃B outside the editor.** ⌃B is tmux's prefix key, and
  this app has terminal panes. This is `CodeView.doCommand` and nothing else —
  no global shortcut, no menu item, nothing that could take ⌃B before a
  terminal sees it.

## Found and ruled out on the way

- **⌃O used to do nothing and now steps the caret back one character. Filed as
  [0499](../open/0499-o-steps-the-caret-back-one-character-and-opens-no-line.md).**
  This is the one thing in this item that had to be looked for rather than
  found: `StandardKeyBinding.dict` binds `^o` to a *pair* of selectors,
  `['insertNewlineIgnoringFieldEditor:', 'moveBackward:']`. The first has no
  case here and the second now does, so a key that was inert became half of
  open-line. Watched with a probe and the probe taken out again:

      EMACS: at 2@6      caret=50 selection=50..<50 “”
      EMACS: ⌃O          caret=49 selection=49..<49 “”
      EMACS: PROBE after ⌃O third line of the file

  Not fixed here. The obvious one-liner —
  `insertNewlineIgnoringFieldEditor:` → `insertNewlineWithIndent()` — decides
  by accident what open-line does about the indent it copies, and that is a
  decision nobody has made.

- **⌥↑ and ⌥↓ are the same story and are the reason to look for it.** ⌃O was
  not found by pressing keys at random. `StandardKeyBinding.dict` has exactly
  **three** bindings whose value is a *list* of selectors rather than one, and
  all three begin with a selector this item just gave a case to:

      plutil -convert json -o - …/AppKit.framework/Resources/StandardKeyBinding.dict

      '^o'   -> ['insertNewlineIgnoringFieldEditor:', 'moveBackward:']
      '~↑'   -> ['moveBackward:', 'moveToBeginningOfParagraph:']
      '~↓'   -> ['moveForward:', 'moveToEndOfParagraph:']

  A list is sent in order, and a selector nobody handles is skipped rather
  than stopping the rest — so a binding whose halves are split between handled
  and unhandled does half of itself. ⌥↑ and ⌥↓ were dead in both halves
  yesterday and now do the first one:

      EMACS: at 2@6      caret=50 selection=50..<50 “”
      EMACS: ⌥↑          caret=49 selection=49..<49 “”
      EMACS: at 2@6      caret=50 selection=50..<50 “”
      EMACS: ⌥↓          caret=51 selection=51..<51 “”

  Cocoa's ⌥↑ is "step back one, then go to the start of this paragraph" — the
  step back is what makes it move to the *previous* paragraph when the caret
  is already at the start of one. On its own it is a one-character motion on a
  key that should make a paragraph-sized one, which is worse than the dead key
  it replaced on a pair of keys people actually press.

  **Not fixed here, and it does not want its own item.** The second half of
  both is `moveToBeginningOfParagraph:`/`moveToEndOfParagraph:`, which is
  exactly what **0498** is: give those two cases and ⌥↑ and ⌥↓ complete
  themselves, with no line written for them specifically. Recorded in 0498 as
  the reason to take it sooner rather than later.

  This is also the general lesson, and it is worth more than the three keys:
  **adding a case to `doCommand` can change a key that does not appear in the
  diff**, because AppKit sends some bindings as sequences. The three above are
  the whole set today, and the `plutil` line is how to ask again.

- **No unit test, and there is nowhere honest to put one.** The same answer
  0495 reached, for the same reason: this is a `switch` case sending a selector
  to a function that already exists and is already exercised by ← and →.
  `CodeView` lives in `AbydosApp` and needs a window; the one test target is
  `AbydosKitTests`. A pure type mapping two selector names to a delta of ±1
  would be a test of the test. The before-and-after driver runs are the check,
  which is why the step asked for a watched one.

- **The first driver run reported a caret in a file nobody had opened.** It
  said `caret=26` in a document whose last line was `alias dc="docker
  compose"` — a tab the previous session had left. `--file` is opened some
  time after launch and the drivers fire 1.2 seconds in, and on a project
  directory the app has never seen before the file has not arrived yet.
  Reproduced on purpose against a second, fresh directory, so it is the
  behaviour and not a one-off. **Not fixed by making the wait longer** — a
  bigger number is the same race — but the driver now prints what document it
  is on, which turns twenty minutes of reading correct-looking offsets into
  one line. The second run of the same command line is fine, because by then
  the project is one the app knows.

- **A driver that presses a deleting key edits the file it was pointed at.**
  The ⌃D in the family probe really did delete the `l` from `third line`, and
  the app **autosaved it to disk**: the next run reported `⇧⌃F … “i”` and `⌃N
  … caret=72`, one offset short all the way down, and read like a motion bug.
  The scratch file was rewritten and the run repeated. Anything that presses
  ⌃D, ⌃K or ⌃O through a driver should assume the file on disk changes.

- **No menu item takes any of these four keystrokes, and that is the app's own
  answer rather than a grep.** `--menu-keys` lists every key equivalent with
  the layout applied; the ones with Control in them are ⌃R, ⌃D, ⌃⇧P, ⌃⌘R,
  ⌃⌘T, ⌃⌘D, ⌃⌘F, ⌃⌘P, ⌃⌘Space and ⌃⌘1-4. **⌃B, ⇧⌃B, ⌃F and ⇧⌃F appear
  nowhere**, so nothing is in front of the editor for them and the item's
  ruled-out constraint holds without anything being added to keep it. Worth
  doing this way round because the driver *cannot* answer it: it synthesises a
  `keyDown` straight into the code view, which is the right way to prove a
  binding reaches the editor and skips exactly the dispatch a menu item would
  win. ⌃D is the proof that the difference is real — the driver sees
  `deleteForward:`, the app has Run ▸ Debug on it.

- **One `simulateKey`, not a second function beside `simulateArrow`.** Its own
  comment already argued this when Page Up joined it — "a second function
  differing only in a key code would be the one somebody forgets to keep up
  with this one" — and a letter key differs by more than a key code, which
  makes the argument stronger rather than weaker. The rename touches three
  files and six call sites and no behaviour.

- **The ⇧ in ⇧⌃F is not decoration in the synthesised event.** A letter held
  with Control reports the control character in `characters` and the bare
  letter in `charactersIgnoringModifiers`, with Shift reaching only the
  second. An event built with the same string in both fields is not the event
  a keyboard sends, and the binding it matches is not the one intended.

- **`simulateTyping`'s doc comment had drifted onto the function below it**
  and was two paragraphs above the function it describes, glued to
  `simulateArrow`'s. Moved back, since this item rewrote the comment it was
  stuck to.

- **RTL was not built, and the decision above says why not.** What was
  *checked* is that nothing in this repository's Swift mentions bidi at all,
  so there is no half-built visual order this change contradicts. What is left
  is a real gap — `CTLine` reorders when it draws and the motions do not — and
  it is unchanged by this item, not created by it.

## Estimate

2026-08-16 11:51 — half an hour left

## Steps

- [x] `moveForward:` and `moveBackward:` move the caret one character
- [x] `moveForwardAndModifySelection:` and `moveBackwardAndModifySelection:`
      extend the selection the same way
- [x] Decide about logical against visual order, and write the answer down
      whichever way it goes
- [x] The rest of the emacs family: press it once and file what is missing,
      rather than guess which of ⌃A, ⌃E, ⌃D and ⌃K are worth an item

      Added while doing the work. The item said the rest of the family was a
      separate decision and left it at that; it costs one driver run to make
      that decision on evidence instead. ⌃D works, ⌃A, ⌃E and ⌃K do not, and
      **0498** says why — they are the paragraph selectors, not the line ones.
- [x] A driver that can press a letter key with a modifier at all —
      `simulateArrow` knew the four arrows and the two page keys and nothing
      else, so there was no way to press ⌃B through `keyDown`

      Added while doing the work: the item assumed 0494's driver could be
      extended, and it could not reach these keys without being widened first.
      It is `simulateKey` now, and `--emacs-nav` is beside `--word-nav` and
      `--vertical-nav`.
- [x] Watched from outside the app: ⌃B, ⌃F, ⇧⌃B and ⇧⌃F, with the caret
      mid-line, and ⌃B at the start of a line to see what it does at an edge

      Before as well as after, the before run made by stashing the `doCommand`
      change and rebuilding rather than by remembering what it used to do.
- [x] `make test` and `make warnings` are clean

      2610 tests in 365 suites passed. `make warnings` says no warnings in
      this repository's Swift, with the four vendored tree-sitter C warnings
      it always reports.
- [x] Every binding that sends one of these selectors as part of a *sequence*,
      because those keys change without appearing in the diff

      Added while doing the work, and it found two keys nobody would have
      looked at: ⌃O, and ⌥↑/⌥↓. See "Found and ruled out" — three bindings in
      `StandardKeyBinding.dict` are lists, and all three begin with a selector
      this item gave a case to.
- [x] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says what the project now does, beside what 0494 and
      0495 put there about the arrows
