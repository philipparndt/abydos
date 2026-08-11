# 467. The footer says nothing about a server that is answering

0463 shipped the chip this morning and the first real file it was tried on has
no chip. `/Users/philipparndt/dev/smarthome/projects/mqtt-lamarzocco/app/main.go`
shows `249:34   Go` and nothing to the left of it, and gopls is up and answering
for exactly that directory:

    12:44:26 gopls started for go at .../mqtt-lamarzocco/app [/Users/philipparndt/go/bin/gopls]
    12:44:26 gopls initialized
    12:44:26 gopls says [info] Created View (#1) directory=.../mqtt-lamarzocco/app/
             view_type="GoMod" go_version="go version go1.26.5 darwin/arm64"
    12:44:26 gopls says [info] go/packages.Load … packages=6 duration=173ms

The app running is the 12:38 install, which is after both the 0463 merge (10:44)
and the 0461 merge (10:53), so this is not a stale binary. gopls is on the
machine at `~/go/bin/gopls`, so the state should be `.answering` with
`.installed`, and the chip should read `gopls` and nothing else.

## The layout is not the cause

`EditorStatusView.draw` lays out right to left — language at the edge, position
to its left, then `drawServer(leftOf:)`. The screenshot has the language flush
right and the position beside it with empty bar to the left, which is where the
chip would be. So `serverText` is empty, which means
`LanguageService.footer(forLanguage:project:)` returned nil, and the question is
why it returned nil for a server that is running.

## The likely cause, which is older than 0463

`footer(forLanguage:project:)` looks up `servers[key(project:languageId:)]` — it
rebuilds the key from **the group's project** and the file's language. But which
server holds a document is not always derivable that way, and this codebase
already knows it: `documentServers` exists for exactly this, and the comment over
it says so —

> when that is not noticed — the file was announced to the repository's server
> and asked about under the subproject's

`opened(url:languageId:text:project:)` records `documentServers[uri] = key` at
the key the document was really opened under. **The footer never consults it.**
So wherever the group's project and the project a document was opened under
differ — a subproject, a scope that moved — the chip goes blank while every
question the file asks is answered normally, because questions go through the
recorded key and the chip does not.

That would explain silence with no other symptom, which is what this is.

**The fix, if this is it, is one line of lookup and one of design:** the chip
follows the *file*, so it should ask what server that file is open at, and fall
back to the language-and-project key only for a file no server holds. Both the
strip and the chip are refreshed together in `refreshServerState()` and the strip
has the same weakness, so whatever is decided should be decided for both.

## The other candidate, and how to tell them apart in two seconds

A refresh that never came. `.ideaiLanguageServersChanged` is posted after a
successful handshake and `refreshServerState()` is on it, so a chip that is blank
until something else forces a redraw would mean the post and the observer are not
meeting — a different bug in the same code.

**Switch to another tab and back.** If the chip appears, it is the missed
refresh. If it stays blank, it is the key. Do this before writing any code; the
two fixes are in different places.

## What it turned out to be: neither. The chip was drawn and thrown away

Both candidates above are wrong, and the reproduction says so in numbers rather
than by argument. `EditorStatusView.drawServer` asked

    let width = min(size.width, room)
    guard width >= Theme.current.scaled(56) else { return }

`width` is what the chip would *measure*, not the room it has. `gopls` measures
30 points. Thirty is less than fifty-six in an editor of any width, so the chip
was computed, pushed, held, and then dropped by the last line before it was
drawn — over a server that was answering, with 1204 points of empty bar beside
it. Every short server name had it: `gopls`, `clangd`, `zls`, `bashls`.

The floor was meant for a chip being **cut** — `ru…` says nothing anybody can
use — so the question is about the room, and a name that fits is drawn whatever
its length:

    guard room >= min(text, floor) else { return nil }

**Why nothing caught it.** The rule was geometry inside the app target, where
the suite cannot reach; and every example in `LanguageServerFooterTests`, every
one of the five pictures 0463 took, and the truncation photograph itself all say
`rust-analyzer` with an image tag after it — 200 points, comfortably over the
floor. The one thing never tried was a short name. So the rule now lives in
`LanguageServerFooter.chipWidth(text:room:legibleAt:)`, as a value with four
cases in the suite, and the bar only measures and draws.

## Ruled out, with what ruled it out

Reproduced first, on a **copy** of `mqtt-lamarzocco` in a scratch directory —
same shape (`app/go.mod` under a project root that has none), same blank chip,
gopls started for the copy's `app/` and initialised, all in `lsp.log`.

- **The key, and `documentServers` with it.** Dead. `--report-answer` asks the
  real server through `ready(_:project:for:)`, which builds the key exactly as
  `footer(forLanguage:project:)` does: `outline 7 symbols` and `completion 73
  suggestions` at 857 ms. A key that answers a document-symbol request is not a
  key that fails a dictionary lookup. Confirmed directly afterwards by printing
  the table: the key asked for, the two keys held, and `documentServers` all
  named `<project>#gopls` — one entry, matching. The root gopls is *started* at
  is `app/`, and it never enters the key; the test added for this pins that.
- **A refresh that never arrived.** Dead. The observer fires repeatedly: the
  probe printed `footer=…(gopls, installed, answering)` on every
  `.ideaiLanguageServersChanged` from about a second after launch, and
  `statusServer` was set from the first one. There was nothing wrong with the
  push. The tab switch the item asks for would have shown nothing either, which
  is worth knowing: it is not a discriminating test when the value is right and
  the *drawing* is what drops it.
- **The layout being innocent.** Half right. The item reasons that empty bar to
  the left of the position means `serverText` is empty. The reasoning is sound
  and the conclusion is not — `serverText` was `gopls` the whole time, and
  `draw` ran with it at the moment of capture. What is drawn and what is decided
  are two different questions, and the space between them is where this lived.
- **The strip above the file.** Not at fault, asked and answered. It reaches the
  screen through `LanguageService.notice(forLanguage:project:)` — the same key,
  proven right above — and it has no width rule at all: an `NSTextField` in a
  stack that truncates rather than a floor that drops. On the reproduction it
  correctly said `no banner`, which is what an answering server should leave
  above the file.

**Seen with my own eyes**, on the copy, at 1600×800: `gopls   1:1   Go`, the
name alone with no mark, which is what an installed server wears. Before and
after are in `images/`.

## Estimate

2026-08-11 13:15 — about forty minutes left

## Steps

- [x] Tell the two candidates apart, by the tab switch and then by measurement
- [ ] The chip names the server that holds *this file*, not the one the group's
      project would resolve to

      Not done, and not to be done. The key was measured and it is right — a
      server started at `app/` is still filed under the project, and the footer
      finds it. Making the chip read `documentServers` would be a second lookup
      of the same answer, and the first thing to go stale.
- [x] The same question asked of the strip above the file, which is refreshed
      from the same place and looks up the same way
- [x] Seen on `mqtt-lamarzocco/app/main.go`, which is where it was reported —
      on a copy of it, and the copy showed the same blank chip first
- [x] A test for a file whose server was started under a different root from the
      group's project — the case `documentServers` was built for
- [x] The rule the chip is drawn by is a value the suite can reach, since it was
      the rule that was wrong and the suite could not see it
- [x] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says what the project now does
