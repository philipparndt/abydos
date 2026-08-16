# 499. ⌃O steps the caret back one character and opens no line

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

## Ruled out

- **Doing it inside 0497.** 0497 is two motions and a decision about logical
  order. Open-line inserts text, and it carries the indent question above,
  which nobody has decided. Adding it there would have been a design choice
  smuggled in under a fix for ⌃B.

## Steps

- [ ] Decide what ⌃O does about the indent of the line it splits
- [ ] `insertNewlineIgnoringFieldEditor:` has a case, so ⌃O opens a line
- [ ] Watched with `--emacs-nav`, which already knows ⌃O's key code, on an
      indented line as well as an unindented one
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says what the project now does
