## 1. Remembering an allow

- [x] 1.1 `Preview/AllowedPages.swift`: a store in `ProjectTrust`'s shape — a
  JSON file in Application Support, one entry per resolved file path, `allow`,
  `forget` and `isAllowed`, and `persists = !DrivenRun.isActive` so a driven
  run's decision never reaches somebody's real list.
- [x] 1.2 `AllowedPagesTests`: an allow is remembered and read back, forgetting
  removes it, a path that moves is not allowed, a store given its own file does
  not touch the shared one, and a driven store writes nothing.

## 2. What the pane says

- [x] 2.1 `HtmlPage` gains the sentence an allowed page says, beside
  `RemoteReferences.said` — one place for both, so the two states of the line
  cannot drift apart in wording.
- [x] 2.2 The sentence for a driven run, which is neither of those: the page is
  allowed and a driven run reaches nothing anyway.
- [x] 2.3 Tests for all three, including that an allowed page with no remote
  references says nothing at all.

## 3. The button

- [x] 3.1 `HtmlPreviewView`'s caption becomes a horizontal stack: the sentence,
  then a button pinned to the trailing edge and sized to its title. The sentence
  keeps what is left and still truncates from the tail.
- [x] 3.2 *Load* when something was refused, *Block* when the page is allowed,
  and no button at all when the document names no remote address.
- [x] 3.3 Pressing *Load* records the allow, removes the rule list from this
  pane's content controller and renders again. Pressing *Block* forgets it, puts
  the list back and renders again. The scroll position is kept across both, the
  way it is across an edit.
- [x] 3.4 A pane built for an already-allowed file never adds the list in the
  first place, so an allowed page does not flash its refused state on open.
- [x] 3.5 A driven run adds the list whatever is remembered, and the caption
  says so.

## 4. Checking it

- [x] 4.1 `HtmlPreviewLiveTests` gains the two states of a web view: with the
  list added, a page's own scheme is served and nothing else is; with it
  removed, the same page loads and the handler still sees only its own scheme's
  requests. Neither test fetches anything.
- [x] 4.2 Driven against a scratch project: the button is on the line, pressing
  it is reported, and the run fetches nothing because it is a driven run. The
  pane's report says which state it is in.
- [ ] 4.3 By hand, once, online: a page linking Google Fonts renders unstyled
  with the offer, and styled after it is pressed. This is the one claim no
  suite may make, because a test that fetches is a test that fails on an
  aeroplane.

  **Left for somebody at a screen, deliberately and doubly.** A driven run
  cannot make this claim — it refuses the network by design, which is what the
  run above photographs — so the only way to see a font arrive is to press the
  button in a session somebody is sitting in. Everything up to the fetch is
  checked: the offer appears, pressing it is recorded, the list comes off the
  web view, and the page still gets what is beside it.

## 5. Finishing

- [x] 5.1 `docs/release-notes-<version>.md`: the HTML preview's "Nothing is
  fetched" gains the clause it now needs, in whichever version carries this.

  0.23.0 turned out to be that version rather than a released one: its notes
  were written but the release was never cut — no `v0.23.0` tag exists — so
  they are one document describing what 0.23.0 will be, and the sentence is
  amended there rather than corrected in a later set.
- [x] 5.2 The open question in `design.md` — whether an allowed page still shows
  the count — is answered there once somebody has looked at the line.
- [x] 5.3 `make test` and `make warnings`, both clean, exit codes read rather
  than output skimmed. Any file that grew past its recorded size has its record
  bumped in the same change.

## Notes

No `.abydos/backlog/spec/*.md` file is made untrue: the backlog is retired.
What this makes untrue is the `html-preview` capability in `openspec/specs`,
once the `html-preview` change is archived — its *Nothing is fetched*
requirement is carried here as modified.
