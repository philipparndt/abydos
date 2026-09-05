## Context

Three keys touch a file's indentation and only one of them asks the file.
⇥ with no selection inserts a literal tab (`indentSelectionOrInsertTab` →
`insertTextAtCaret("\t")`); ⇥ over lines and ⇧Tab shift them by a hardcoded
`"\t"` and the setting's display width (`shiftLines` → `LineIndent`); return
asks — `ReturnIndent.usesTabs` samples the top of the buffer per keypress —
but takes the space width from `Theme.current.tabWidth`, so a two-space file
gets the setting's four. There is no state to show, because there is no
state: the answer is recomputed or assumed, never held.

The footer's left side is where a file's facts stand — the SOPS chip at the
edge (a decision made yesterday and standing), the lock after it — and its
right side is position, language and server, drawn right-to-left.

## Goals / Non-Goals

**Goals:**

- One held answer per buffer — the kind, and for spaces the width — read
  from the file's own habit, shown in the footer on the right, chosen from
  a menu.
- Every insertion path follows it: ⇥ (with or without a selection), ⇧Tab,
  block indent, and return's auto-indent including its width.
- Choosing converts the file's indentation to the chosen style, and one ⌘Z
  returns the file to what it was.

**Non-Goals:**

- Not reading `.editorconfig`, an `.editions` file or any project convention:
  the report asks what *this file* does, and the file is what is open.
- Not editing the width by hand anywhere but the menu: the menu offers the
  standing widths and the file's own, and that is the whole of the choice —
  a chip that opened a settings page would answer a question nobody asked.
- Not changing how a tab is *drawn* (`Settings.tabWidth` keeps that job) or
  what the soft-wrap, comment-at-shared-indent and column arithmetic do.
- Not converting alignment: a tab after the first non-blank is a choice
  about one line, not the file's habit, and a conversion that moved it would
  break what it was lining up. Only a line's indentation is converted.

## Decisions

### The style lives on the view that inserts, read twice and set by one door

`CodeView` holds `indentStyle`, read from a bounded sample of the buffer in
`load(document:)` — the same 8 KB window `usesTabsForIndent` samples today —
and again in `replaceAllText`, because a buffer replaced wholesale (a SOPS
decrypt, a lock, an external reload) is a new text whose habit is new. The
menu's choice arrives through `convertIndentation(to:)`, the same
push-don't-pull shape `setConcealsSecrets` uses. `usesTabsForIndent` — a
re-sample on every return keypress — is deleted; a per-keypress scan was a
cost paid to avoid holding one enum, and the footer chip needs the held
answer anyway.

*Ruled out:* the style on the group's `Tab`, beside `isSopsFile` — the view
is what inserts, and a fact two objects must keep agreeing on is a drift
waiting for the first edit that updates only one. The group asks the view,
the way `secretsState` does.

*Ruled out:* keeping the per-keypress detection and deriving the chip from
it — the chip must not flicker as the buffer changes under an edit, and
"decided once, kept" is the rule every other file fact here already follows.

### Detection: which kind the file uses, and how wide its spaces are

One pass over the first 200 non-empty lines: a line beginning with a tab
votes tabs, a line beginning with a space votes spaces and names its run
length. Tabs win ties (`tabs >= spaces`, the rule `ReturnIndent.usesTabs`
already had — a mixed file stays tab-indented, which is the side its
existing lines are on). The width is the most common space run, ties to the
narrower; a file with no space-led lines, or no indented lines at all, falls
back to the app's tab width as spaces, which is what return does today.
`ReturnIndent.usesTabs` folds into this — one detector, one suite — and its
four test claims move with it.

*Ruled out:* the gcd of leading-space counts — one misindented continuation
line (three spaces in a four-space file) collapses the answer to one.
*Ruled out:* the minimum run — one stray one-space line (a markdown list, a
comment) does the same from the other side. The most common run is what a
continuation line cannot outvote, because it appears once and the step
appears at every level.

### The press opens a menu on the right, and choosing converts the file

*Amended on 2026-09-5, the same day, reversing this change's own first cut:
the chip stood on the left after the lock, pressing toggled the kind, and
nothing already in the file was converted. Asked for directly — "the
tabs/spaces toggle should be on the right side of the toolbar and it shall
show a menu. It shall then also convert the file when switched." The
ruled-out alternatives below say what the first cut believed; they stand
amended rather than deleted, because a reversal nobody can read is how the
same decision gets made twice.*

The chip joins the footer's right-aligned row between the caret position
and the language — where the arrangement other editors keep puts it, and
where the two menu-openers (indentation, language) stand side by side.
Pressing pops a menu: *Indent with Tabs*, then *Indent with 2/4/8 Spaces*
with the file's own unusual width offered beside the standing ones, the
current style ticked. The offered widths are one rule in the engine —
`IndentStyle.offeredWidths` — read by the menu and by the driven report
alike, so the two cannot drift.

Choosing converts the buffer's indentation level by level — one leading
level of the old style (a tab, or the old width in spaces) becomes one level
of the new — and makes the chosen style the one inserted from here.
Alignment after the first non-blank is left alone; a partial level keeps its
spaces; a tabs file's stray leading spaces are kept as they are, the style
having no intent to read into them. The conversion is one rope replace —
the cost of a paste, one undo node, the caret and folds put back the way a
wholesale replacement puts them — and the chosen style is set *after* it, over
the re-read the replacement does: a conversion is the one replacement whose
style is known without reading the buffer, because it was chosen — a file
converted to tabs that has no indented line yet must not fall back to spaces
the moment its own menu item is taken.

*Ruled out by the first cut, standing amended:* the left side beside the
lock — the file's facts read well, but the request names the right side,
where the indentation chip of every other editor already lives and where
somebody who knows the convention goes looking. *Ruled out by the first
cut, standing amended:* a bare toggle — the request names a menu, and a menu
can offer the standing widths beside the file's own, which a toggle cannot.
*Ruled out by the first cut, standing amended:* converting nothing — the
request converts, and a conversion with one undo behind it is honest to ask
for; the no-conversion rule guarded against a silent rewrite, and a menu
choice is anything but silent.

## Risks / Trade-offs

- [Return's auto-indent changes width in files that relied on the setting]
  → it is the report's own case: a two-space file whose return indented by
  the setting's four now indents by two. Said in the release notes with the
  before and after, not left to be found as a bug.
- [A file with a genuinely mixed habit] → the counts pick the side its lines
  are mostly on and the chip says so out loud, which is more than the old
  behaviour (tabs, silently, whatever the file) ever told anybody. The menu
  settles any disagreement by hand.
- [`CodeView.swift` sits at its ceiling] → the style adds to a file at 4585
  and deletes the detection it replaces; the finishing task checks and
  raises the ceiling for what remains, the debt the file records.
- [The right side grows by one chip] → it is drawn inside the right-aligned
  row, so what it costs is room the truncating server chip must give up on a
  narrow window — and the left chips' extent is measured into that room now
  too, which closes an overlap the lock and the SOPS chip could already
  reach before this change.
- [A conversion on a huge file] → one rope replace, the cost of a paste over
  the same span; nothing per line, nothing per level beyond the one pass.

## Migration Plan

None. Detection is a read, the chip a view, and the inserted unit a
keypress; nothing stored changes shape.

## Open Questions

None — the report names the behaviour, the SOPS chip names the shape of the
footer control, and return names the rule that the file beats the setting.