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

## Worth deciding — decided

**⌃O inserts a bare newline and carries no indent**, and the reason is not
taste: it is the only insertion that composes with the `moveBackward:` that
macOS sends after it.

    case #selector(insertNewlineIgnoringFieldEditor(_:)): insertTextAtCaret("\n")

The two selectors arrive in order and the second one is a plain one-character
step. So whatever the first inserts, the caret ends up **one composed
character back from wherever the insertion left it** — and the key is only
open-line if that lands the caret exactly where it started. A bare `\n` moves
the caret by one, and one back from one is zero. `insertNewlineWithIndent()`
moves it by one plus the indent, so on `⇥⇥foo|bar` the caret would finish
*between the two tabs*: not where it was, not on the new line, and one short
of the end of an indent it just wrote. The item feared a one-liner would
decide this by accident; what is true is that only one of the two one-liners
is `open-line` at all.

Two more things `insertNewlineWithIndent()` would have dragged in, both
visible in what it is for rather than in what it does:

- **It is Return's function, and Return moves the caret to the new line.**
  Copying the indent is right there because somebody is about to type at the
  new indent. ⌃O's caret does not go to the new line, so the copy would be
  whitespace on a line nobody is on — trailing whitespace written by a key
  the user pressed to keep their place. At the end of an indented line, which
  is the case the item asked about, the whole of what ⌃O adds *is* that empty
  line, so an indent-copying ⌃O would produce a line of nothing but tabs
  every time it was pressed there.
- **`ReturnIndent.result` splits brace pairs.** Return between `{` and `}`
  puts the closing brace on its own line and drops the caret on the blank
  line between the halves. `moveBackward:` from there is arbitrary — it is a
  caret position chosen by a different feature, stepped back one character by
  a key that knows nothing about it.

Cocoa's own ⌃O and emacs `open-line` both insert a bare newline, so this
agrees with the two things anybody pressing this key has used it in. The
answer for a caret **mid-word** is therefore the plain one: `third li|ne`
becomes `third li` and `ne of the file`, with the caret still after the `i`
of `li`. Nothing is re-indented, and the second half keeps column 0 whatever
the line was indented to — which is `open-line`, not Return, and is why the
two keys stay two functions.

### The input the two halves were expected not to cancel on, and do

A caret immediately after a **lone `\r`** is the one place the newline could
have made the step back bigger than the step forward: `\r\n` is a single
*grapheme*, so a caret motion that moved by graphemes would step over both
and finish one character to the left of where ⌃O started. It does not,
because `moveHorizontally`'s alignment is not grapheme alignment —
`Rope.alignToBoundary` walks back over UTF-8 **continuation bytes** and
nothing else, and `\n` is not a continuation byte. Watched, with a probe that
was taken out again, on a file whose first line is `abc\rdef ghi` — the raw
`\r` the driver printed is written `␍` here, since a real one moves a
terminal's cursor to the start of the line:

    EMACS: PROBE cr    caret=4 selection=4..<4 “”
    EMACS:             line 0 “abc␍|def ghi” then 1 “xéy and more text” — 12 lines
    EMACS: ⌃O          caret=4 selection=4..<4 “”
    EMACS:             line 0 “abc|” then 1 “def ghi” — 13 lines

Caret 4 before and 4 after, and a line more in the file: the two halves
cancel here as everywhere else. The caret is left between the `\r` and the
`\n` it just inserted, which is inside the line terminator and is why the
report draws it at the end of `abc` — `lineByteRange` trims CRLF, so the
column clamps to the end of the line. Nothing to handle, and nothing about
⌃O to write down; what came out of this probe was about ⌃F instead, and is
under "Found and ruled out" below.

## Worth deciding — as the item filed it

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
    EMACS:             line 5 “|” then 6 “sixth lines” — 9 lines
    EMACS: ⌃O          caret=122 selection=122..<122 “”
    EMACS:             line 4 “⇥indented fifth line of the file|” then 5 “” — 9 lines
    EMACS: at 4@end    caret=122 selection=122..<122 “”
    EMACS:             line 4 “⇥indented fifth line of the file|” then 5 “” — 9 lines
    EMACS: ⌃O          caret=121 selection=121..<121 “”
    EMACS:             line 4 “⇥indented fifth line of the fil|e” then 5 “” — 9 lines
    EMACS: at 2@8      caret=51 selection=51..<51 “”
    EMACS:             line 2 “third li|ne of the file” then 3 “fourth line of the file” — 9 lines
    EMACS: ⌃O          caret=50 selection=50..<50 “”
    EMACS:             line 2 “third l|ine of the file” then 3 “fourth line of the file” — 9 lines

Every line is the same text one character to the left, and the count stays at
nine: **the file never gains a line**, and **⌃O is `moveBackward:` and
nothing else**, which is the report at the top of this item watched rather
than reasoned about. The empty-line
press is the clearest of the three — the caret leaves the empty line
altogether and ends up at the end of the line above, which is a key that
should have *added* an empty line moving the caret off the one that was
already there.

**After**, the same driver against the same file, rebuilt with the one case
added:

    EMACS: at 5@0      caret=123 selection=123..<123 “”
    EMACS:             line 5 “|” then 6 “sixth lines” — 9 lines
    EMACS: ⌃O          caret=123 selection=123..<123 “”
    EMACS:             line 5 “|” then 6 “” — 10 lines
    EMACS: at 4@end    caret=122 selection=122..<122 “”
    EMACS:             line 4 “⇥indented fifth line of the file|” then 5 “” — 10 lines
    EMACS: ⌃O          caret=122 selection=122..<122 “”
    EMACS:             line 4 “⇥indented fifth line of the file|” then 5 “” — 11 lines
    EMACS: at 2@8      caret=51 selection=51..<51 “”
    EMACS:             line 2 “third li|ne of the file” then 3 “fourth line of the file” — 11 lines
    EMACS: ⌃O          caret=51 selection=51..<51 “”
    EMACS:             line 2 “third li|” then 3 “ne of the file” — 12 lines

Three presses, three lines gained, and **the caret offset is identical either
side of every one of them** — 123, 122, 51 — which is the whole of what
open-line promises and is exactly what the before run could not do.

- **Mid-word**, the third pair: `third li|ne of the file` becomes `third li`
  and `ne of the file`, caret still at 51, still after the `i`. The second
  half starts at column 0 and is not re-indented.
- **The end of an indented line**, the second pair: line 4 is unchanged with
  the caret still at its end, and the line that appears under it is `“”` —
  **empty, not `⇥`**. That is the indent decision, watched. Only the count
  says a line was inserted at all, because the line after an insertion at the
  end of a line is empty either way; that is why the report prints it.
- **An empty line**, the first pair: the caret stays on line 5 and an empty
  line 6 appears above `sixth lines`. Compare the before run, where the same
  press moved the caret *off* the empty line and onto the end of line 4.

The ⌃B, ⌃F, ⌃P and ⌃N part of the driver is unchanged between the two runs,
which is the control: this file is not 0497's, so its offsets differ from the
ones in that item, but they are the same in both runs here.

## Found and ruled out on the way

- **A decomposed accent is two steps of ⌃F, not one, and `spec/editor.md`
  says otherwise.** The CR probe above needed a claim about what
  `moveHorizontally` aligns to, and the answer — UTF-8 code-point boundaries,
  not graphemes — makes 0497's sentence "an emoji or a letter with a
  combining mark is one step and not two" true for the emoji and false for
  the combining mark. An emoji is one code point; `e` + U+0301 is two.
  Watched with the same throwaway probe, on a line whose second character is
  a decomposed `é` starting at offset 13:

      EMACS: PROBE mark  caret=13 selection=13..<13 “”
      EMACS: ⌃F          caret=14 selection=14..<14 “”

  13 → 14 leaves the caret between the `e` and its acute. 0497 watched the
  emoji, which is why this got through: the one case it ran is the one case
  the code gets right. **Not fixed here** — it is ←, →, ⌃B and ⌃F together
  and it is a change to `Rope.alignToBoundary` or to its caller, which is a
  different thing from giving ⌃O a case. Filed as
  [0504](../open/0504-a-decomposed-accent-is-two-steps-of-f-and-the-spec-says-one.md),
  which also carries the spec sentence: the requirement 0497 wrote says an
  emoji *or a letter with a combining mark* is one step, and half of that is
  untrue today. Left for 0504 rather than corrected here as a `MODIFIED`,
  because the sentence describes what the editor is meant to do and 0504 is
  the item that makes it so — and because 0502 is editing the same file in
  another worktree this week, and a delta that rewrites a requirement it may
  also be touching is a conflict bought for nothing.

- **The driver's first run reported a file nobody had opened, again.** 0497
  wrote this down and it still cost a run: the CR probe's first go printed
  `line 0 “alia|s dc="docker compose"”`, a tab from an old session, because
  `--file` had not arrived 1.2 seconds in on a project the app had never
  seen. The second run of the same command line is right. Worth repeating
  here only because the file that run *did* edit was the wrong one.

- **A ⌃O run leaves the scratch file changed on disk.** 0497 warned about it
  for ⌃D and it is true of this key: the CR probe's file came back with the
  split written into it. Every run above rewrites the file first, which is
  the cheap fix and the reason none of the transcripts drift.

- **No unit test, for the third item running.** `CodeView` lives in
  `AbydosApp` and needs a window; the one test target is `AbydosKitTests`.
  What this item adds is a `switch` case calling `insertTextAtCaret`, which
  ⇧Return already exercises, and the part that is actually new — that two
  selectors from one key compose — cannot be tested below the level of the
  key binding at all, because it is `interpretKeyEvents` that sends the
  second one. The before-and-after driver runs are the check.

## Ruled out

- **Doing it inside 0497.** 0497 is two motions and a decision about logical
  order. Open-line inserts text, and it carries the indent question above,
  which nobody has decided. Adding it there would have been a design choice
  smuggled in under a fix for ⌃B.

## Estimate

2026-08-16 09:05 — about two hours left

## Steps

- [x] Decide what ⌃O does about the indent of the line it splits
- [x] `insertNewlineIgnoringFieldEditor:` has a case, so ⌃O opens a line
- [x] A driver that shows the *text* ⌃O leaves behind, not only the caret

      Added before starting. `caretReportForTesting` prints the selected
      text, which is empty for a collapsed caret, so open-line — whose whole
      point is that the caret does not move — prints exactly what a dead key
      prints. 0497 read this off a `PROBE` line it took out again; a key that
      inserts text needs the text in the transcript.
- [x] Watched with `--emacs-nav`, which already knows ⌃O's key code, on an
      indented line as well as an unindented one

      Before as well as after, the before run made by stashing the
      `doCommand` case and rebuilding. Mid-word, at the end of an indented
      line and on an empty line, with the lines printed as well as the caret.
- [x] `make test` and `make warnings` are clean

      2625 tests in 367 suites passed. `make warnings` says no warnings in
      this repository's Swift, with the four vendored tree-sitter C warnings
      it always reports.
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says what the project now does
