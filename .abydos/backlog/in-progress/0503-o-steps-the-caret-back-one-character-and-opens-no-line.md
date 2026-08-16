# 503. ⌃O steps the caret back one character and opens no line

⌃O is emacs `open-line`: it puts a newline in and leaves the caret in front of
it, so the line splits and you stay where you were. macOS binds it in
`StandardKeyBinding.dict` as **two** selectors, sent in order:

    ^o  ['insertNewlineIgnoringFieldEditor:', 'moveBackward:']

`CodeView.doCommand` has a case for `insertNewline:` and for `insertLineBreak:`
and none for `insertNewlineIgnoringFieldEditor:`. So the first half is dropped
and only the second half runs — and since **0497** the second half works. ⌃O
now moves the caret one character to the left and changes nothing else.
Watched, with 0497's `--emacs-nav` driver and a probe that was taken out again:

    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌃O          caret=49 selection=49..<49 “”
    EMACS: PROBE after ⌃O third line of the file

Before 0497, both halves fell through `default:` and ⌃O did nothing at all.
**This item exists because 0497 made it into a half-key**, which is the shape
0494, 0495 and 0497 were each filed to remove. Nobody has reported ⌃O; what is
being reported here is that a key which used to be inert now does the second
half of something.

## Worth deciding

- **What open-line means with automatic indentation.** `insertNewline:` here
  goes to `insertNewlineWithIndent()`, which copies the leading whitespace of
  the line. Cocoa's ⌃O inserts a bare `\n` and steps back one character, so on
  an indented line the copy-the-indent version leaves the caret *inside* the
  new indent rather than at the end of the old line. Doing the obvious
  one-liner — `insertNewlineIgnoringFieldEditor:` → `insertNewlineWithIndent()`
  — decides this by accident. It is the only real question in the item and it
  is why 0497 filed this instead of adding the line.
- **Or make ⌃O inert again**, which cannot be done in the switch: the two
  selectors arrive separately and `moveBackward:` from ⌃O is indistinguishable
  from `moveBackward:` from ⌃B. It would need the key event rather than the
  selector, which is a worse trade than either of the two above.

## Watched in the app

`--emacs-nav`, 0497's driver, with a ⌃O section added to the end of it. The
file is eight ordinary short lines, an indented one and an empty one among
them:

    0  first line of the file
    1  second line of file
    2  third line of the file
    3  fourth line of the file
    4  →indented fifth line of the file
    5
    6  sixth lines
    7  seventh and last line of the file

**Before**, with the app built from `main` plus the driver and nothing else —
the `doCommand` case was written afterwards, so this is the program as the
item found it:

    $ build/Abydos.app/Contents/MacOS/Abydos --open …/emacs --file …/emacs.txt --emacs-nav

    EMACS: at 5@0      caret=123 selection=123..<123 “”
    EMACS:             line 5 “|” then 6 “sixth lines”
    EMACS: ⌃O          caret=122 selection=122..<122 “”
    EMACS:             line 4 “⇥indented fifth line of the file|” then 5 “”
    EMACS: at 4@end    caret=122 selection=122..<122 “”
    EMACS:             line 4 “⇥indented fifth line of the file|” then 5 “”
    EMACS: ⌃O          caret=121 selection=121..<121 “”
    EMACS:             line 4 “⇥indented fifth line of the fil|e” then 5 “”
    EMACS: at 2@8      caret=51 selection=51..<51 “”
    EMACS:             line 2 “third li|ne of the file” then 3 “fourth line of the file”
    EMACS: ⌃O          caret=50 selection=50..<50 “”
    EMACS:             line 2 “third l|ine of the file” then 3 “fourth line of the file”

Every line is the same text one character to the left, and the file never
gains a line: **⌃O is `moveBackward:` and nothing else**, which is the report
at the top of this item watched rather than reasoned about. The empty-line
press is the clearest of the three — the caret leaves the empty line
altogether and ends up at the end of the line above, which is a key that
should have *added* an empty line moving the caret off the one that was
already there.

## Ruled out

- **Doing it inside 0497.** 0497 is two motions and a decision about logical
  order. Open-line inserts text, and it carries the indent question above,
  which nobody has decided. Adding it there would have been a design choice
  smuggled in under a fix for ⌃B.

## Estimate

2026-08-16 09:05 — about two hours left

## Steps

- [ ] Decide what ⌃O does about the indent of the line it splits
- [ ] `insertNewlineIgnoringFieldEditor:` has a case, so ⌃O opens a line
- [x] A driver that shows the *text* ⌃O leaves behind, not only the caret

      Added before starting. `caretReportForTesting` prints the selected
      text, which is empty for a collapsed caret, so open-line — whose whole
      point is that the caret does not move — prints exactly what a dead key
      prints. 0497 read this off a `PROBE` line it took out again; a key that
      inserts text needs the text in the transcript.
- [ ] Watched with `--emacs-nav`, which already knows ⌃O's key code, on an
      indented line as well as an unindented one
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says what the project now does
