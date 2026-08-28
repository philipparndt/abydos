# Design

## Context

`FindBar` is one row: a search field, a status label, three option toggles, and
four buttons. `EditorViewController` owns the searching — `runFind` debounced at
120 ms, `stepMatch` for ⌘G, and `Tab.FindState` holding each tab's query,
options, matches and current index. The search itself is
`TextSearch.matches(in:query:options:)` over the tab's `Rope`, and it is pure:
text in, ranges out, tested in `AbydosKitTests`.

Editing goes through `TextDocument.replace(utf16Range:with:caretBefore:)`, which
applies one edit to the rope, coalesces contiguous typing into one undo entry, and
records everything else as an entry of its own in an `UndoTree`. Every edit fires
`onLinesChanged(first, removed, inserted)`, which `CodeView` forwards and
`EditorViewController` already fans out per tab.

Two constraints shape everything below. Anything worth a test has to be a value
in `AbydosKit`, because `Tests/` covers nothing in `AbydosApp`. And the re-run on
edit happens on every keystroke in every file that has a find open, so its cost is
part of its design rather than something to measure afterwards.

## Goals / Non-Goals

**Goals:**

- Replace what find found, one match or all of them, from the bar that found it.
- Regular expressions in the replacement as well as in the pattern.
- Replace All is one undo.
- The highlights are true after every edit, from any source.

**Non-Goals:**

- Replacing across a project. That is the search pane's subject and a different
  set of questions — which files, what to do about ones that are open, what to do
  about ones that fail to write.
- Replacing within a selection only. It is the next thing somebody asks for and
  it is a second scope to get right; not here.
- Preserving the case of what was replaced, as some editors offer.
- Anything in the PDF find path. PDFKit finds; there is nothing to edit.

## Decisions

### The bar keeps one class and grows a second row

`FindBar` gains a mode and a second row — the replacement field, Replace, and
Replace All — laid out under the first and hidden in find mode. The bar's height
goes from 34 to 34 plus the row, which is what `findBarHeight` is already there to
animate.

The query, the three switches and the status label are shared, because they are
shared: replacing with `.*` on means the pattern and the template are one
question, and a replace field that had its own copy of the options would be a
second place for them to disagree.

*Ruled out: a separate `ReplaceBar` under the find bar.* Two views, two owners of
the same three switches, and every message from the editor delivered twice.

*Ruled out: a sheet or a floating panel.* The find bar is a strip on purpose —
"it never covers the code you are searching" — and a replace panel would cover
the very lines it is about to change.

### ⌘R switches the mode; ⌘F never switches it back

⌘R opens the bar in replace mode and puts the keyboard in the replacement field.
⌘F opens the bar, focuses the query, and leaves the mode as it found it.

The asymmetry is deliberate. Somebody in the middle of a replace who presses ⌘F
to re-read the query has not asked for the replacement they typed to be taken off
the screen. Making ⌘F collapse the row is a keystroke that discards work with no
way to ask for it back.

⎋ closes the whole bar, which is what it does today, and the mode goes with the
tab like the query does — `Tab.FindState` gains `replacement` and `isReplacing`.

*Ruled out: ⌘⌥F, which is what some editors use.* ⌘R is free here, it is what
this app's user asked for, and the Run menu's ⌃R is a different chord.

### What a replacement means lives in `AbydosKit` and is a value

`TextSearch` gains two things: what one match becomes given a template and the
options, and the list of edits a Replace All makes. Both are functions of text,
query, options and template — no view, no document, no undo — which is what makes
them the only part of this that can be tested.

With `.*` off, the template is literal: `$1` is a dollar and a one. With it on,
the template is `NSRegularExpression`'s, so `$1` is the first capture and `$0` is
the whole match — the semantics of the engine already doing the searching, rather
than a second dialect invented here.

*Ruled out: implementing capture substitution by hand.* It is
`NSRegularExpression.replacementString(for:in:offset:template:)`, it is already
linked, and a hand-rolled version would differ from the search engine in exactly
the corners nobody tests.

### Replace All is one edit over the range the matches span

The edits are computed for the whole set, then applied as a single
`TextDocument.replace` over the range from the first match's start to the last
match's end, with the new text of that span. One edit, one undo entry, one
reparse, one `onLinesChanged`.

*Ruled out: applying the matches one at a time, back to front.* It is the obvious
implementation and it makes 199 undo entries for one gesture, which the proposal
rules out, plus 199 reparses of the file.

*Ruled out: grouping in `UndoTree`.* A real grouping API is the better long-term
answer and is a change to the undo model — the one part of this editor where a
mistake destroys work. It is not worth opening for a feature that can be one edit
without it.

The cost of the covering-range approach is honest and worth stating: matches at
the top and bottom of a file mean rewriting nearly all of it. That is what a
whole-file Replace All does in any case, and tree-sitter is given one edit rather
than hundreds.

### An edit moves the matches at once, and the search is asked again after

On `onLinesChanged` the tab's matches are adjusted immediately, in place: a match
entirely before the edit is kept, a match overlapping it is dropped, a match after
it is shifted by the edit's delta. Then the search is scheduled on the debounce
that already exists, and its answer replaces the adjustment.

Both halves are needed and each is wrong alone. The adjustment alone reports
matches that no longer match — an edit inside a match's own line can leave a range
whose text has changed. The re-run alone leaves the bands wrong for 120 ms after
every keystroke, which is exactly the picture in the proposal, only briefer.
Together, nothing wrong is ever drawn and nothing is recomputed per keystroke.

Keeping the current index across the adjustment is what stops ⌘G jumping to the
top of the file after every character typed.

*Ruled out: clearing the matches on edit and re-running.* Simpler, and it makes
the highlights flicker off and on while somebody types, which is worse than the
bug for anybody who types with find open.

*Ruled out: anchoring matches to their text, the way breakpoints are anchored.*
Breakpoints are few, long-lived and worth following through a rewrite. Matches are
many, cheap and derived — the right answer for them is to ask again.

### The hook is the document's edit, fanned out through the view

`TextDocument.onTextChanged` is a single closure, and the PlantUML, Mermaid and
draw.io panes each assign it. Hanging find on it would take the picture away from
whichever pane the find bar was opened over — a `.puml` file that stopped
redrawing, silently, and looking exactly like a feature that does not work.

**Corrected while implementing.** This first named `onLinesChanged`, which is
wrong in the unit: it carries lines, and a match is a UTF-16 range. The right one
is `onTextReplaced`, described in `TextDocument` as "the same edit in the unit the
view edits in" — which is also a single closure, and also already taken, by the
snippet session. So `CodeView` fans it out the way it already fans out
`onLinesChanged`: the view keeps the document's one closure and offers its own
beside it. The argument is unchanged; only the hook it named was.

### A search an edit asked for keeps the match the edit left current

`runFind` picks the current match by the caret — the first one at or after it —
and `setSearchMatches` leaves the caret at the end of whichever match it made
current. Asked twice, that walks forward: match *k*'s end is before match *k+1*'s
start.

That was invisible while only a typed query re-ran the search. An edit-triggered
re-run makes it visible twice over, and driving it found both: ⌘R over a bar
showing `1 of 4` replaced the *third* match, because opening the bar re-ran a
search whose answer was already in hand; and Replace lit `1 of 3` and became
`2 of 3` a tenth of a second later with nothing having happened.

So the bar does not re-run a search it already has an answer for, and a re-run an
edit asked for keeps the match the adjustment left current, by its range, falling
back to the caret rule only when that match is gone.

*Ruled out: making the caret rule "at or after, or containing".* It fixes the
second symptom and not the first, and it changes what a typed query does, which
is behaviour nobody complained about.

### Replace is offered where there is something to replace

The replace row is shown for a tab with a document and a code view. A PDF tab
keeps the find bar it has: ⌘R does nothing there rather than opening a row whose
buttons cannot work. The `.*` and whole-word switches are already shown but
inactive for PDFs, with a reason written where they are drawn; the replace row is
a different case, because a switch that is ignored still describes the next file
and a Replace button that cannot fire describes nothing.

## Risks / Trade-offs

- **The re-run on every edit costs a full scan of the file** → it is the same
  scan the find field already runs on the same 120 ms debounce, and it runs only
  for a tab with find open. A file large enough for this to matter is a file where
  typing in the find field already costs the same, and the measurement to take is
  the one already taken there.
- **Replace All over a covering range rewrites most of a file** → one edit, one
  reparse. The alternative rewrites the same bytes in hundreds of edits.
- **A regex template with an invalid reference** — `$7` where the pattern has two
  captures → the bar refuses the replacement and says so where it says
  `Incomplete pattern` today, rather than writing an empty string into the file.
- **Undo after Replace All restores the span, caret included** → the caret goes
  back to where the edit began, which is the first match. Somebody who replaced
  and undid is looking at the first thing they changed, which is the right place.
- **⌘R while a modal find is not open** → it opens the bar, seeded from the
  selection like ⌘F, so the shortcut is a way in and not only a way to switch.

## Open Questions

- Whether Replace should step to the next match after replacing, as most editors
  do, or stay where it is. Stepping is the convention and is assumed here; if the
  match it steps to is off-screen, the reveal is the same one find already does.
- Whether the replacement field should keep a small history of what was replaced,
  the way the search field's menu can. Not decided; nothing here forecloses it.
