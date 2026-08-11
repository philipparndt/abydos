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

## Steps

- [ ] Tell the two candidates apart, by the tab switch and then by measurement
- [ ] The chip names the server that holds *this file*, not the one the group's
      project would resolve to
- [ ] The same question asked of the strip above the file, which is refreshed
      from the same place and looks up the same way
- [ ] Seen on `mqtt-lamarzocco/app/main.go`, which is where it was reported
- [ ] A test for a file whose server was started under a different root from the
      group's project — the case `documentServers` was built for
- [ ] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says what the project now does
