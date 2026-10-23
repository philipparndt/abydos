## Why

Asked for on 2026-10-23: "I imagine to have a vboard file and be able to open
this directly in a editor tab, work there and persist it back as a file. The
catch — it must not be a precondition for abydos as it is not publicly
available." And, the same afternoon, what the server is for: "It does not use
a local vboard server but a hosted instance, where the file is then temporary
hosted in an encrypted version and I can collaborate with my colleagues."

vboard is a collaborative whiteboard, and a `.vboard` file is the whole of a
board: its items, the answers given to its widgets, and every picture and PDF
on it as base64 in one JSON document. Today, working on one with colleagues
goes like this: upload it to the hosted vboard in a browser, make it private,
send the link, work, download it again, and put it back where it came from.
Done by hand, that is how a repository ends up with `Retro (1).vboard` beside
`Retro.vboard`, and how a board meant for a one-hour session stays on a shared
server for good. Abydos opens a `.vboard` today as a JSON blob, and over 64 MB
not at all.

The server already has everything a tab needs. This was tried against
`vboard-local` 0.67.0 on the day of the request, which is the same server
program the hosted instance runs:

- `POST /api/v1/boards/import?temporary=true&id=<new id>` with
  `X-Board-Key: <a key Abydos made>` gave `201` and a board that is **private**
  and **temporary**. Without the key, or with a wrong one, the board answers
  `404` as if it did not exist. A word on one of the file's stickies was not
  in the server's database file in plain text.
- That import **kept the file's item ids**, unless they were already used on
  that server. A plain import without `id` gave every item a new id on every
  open (`i_4f0c…` came back as `i_64ae…`).
- `GET …/export.vboard` with the key returned the file in plain form, with
  what was edited in it. `DELETE` with the key removed the board.
- vboard's share link for a private board is `<server>/b/<id>#k=<key>`. A
  browser never sends the part after `#`, so the key reaches the server only
  in a header, from whoever holds the link.

What vboard cannot be is part of the build. It is not publicly available, so
nothing of it can be bundled the way draw.io is (`Scripts/vendor-drawio.sh`),
and no internal hostname may appear in a public repository. The server is the
user's to name.

There is no originating `.abydos/backlog` item: the backlog is retired and this
comes from a direct request.

## What Changes

- **A `.vboard` file opens as a board on the vboard server named in the
  settings.** The file is uploaded as a temporary private board, encrypted
  with a new key Abydos makes for that tab and does not write down. The tab shows
  vboard's own web app on it.
- **The tab can be shared.** *Copy link* puts the board's private link on the
  clipboard. A colleague who can sign in to that server opens it in a browser
  and works on the same board live.
- **Changes on the board are the tab's unsaved changes, whoever made them.**
  ⌘S writes the board as it is now, everyone's edits included, back into the
  file, through a temporary file renamed into place. The edited dot and the
  close prompt work as for a hex tab. It is never auto-saved.
- **Closing ends the session.** The board is deleted from the server. If
  colleagues are still on it, the tab says how many and asks first. *Leave it
  running* is offered, and says that their later edits will not reach the
  file.
- **The tab says where the file is**: the server's host, that the board is
  encrypted there, and that the server can read it while somebody has it
  open. vboard's own documentation says the same about private boards.
- **Somebody else writing the file reloads the board** from the file. The
  web app's own undo is lost, as the draw.io tab loses its undo.
- **Without a server named, a `.vboard` says how to get one** and offers the
  file as text, which is how it opens today. A driven run behaves that way
  whatever is named.
- **Nothing about vboard is required.** No bundled assets, no build step, no
  dependency, no default address, and no test that needs a server unless
  `vboard-local` happens to be installed.

## Capabilities

### New Capabilities

- `vboard-files`: opening a `.vboard` as a private temporary board on a named
  vboard server, sharing it, saving it back to the file, changes from outside,
  ending the session, and what happens when there is no server.

### Modified Capabilities

None. A `.vboard` with no server named opens as JSON, which is what happens
today. A file kind that opens rendered is covered by `previews` without
changing a requirement there.

## Impact

- **AbydosKit**: `Vboard/` (new): the HTTP client for import, export, delete
  and health, carrying the board key as a header and the session cookies of
  the tab's web data store; the link key and the share link; the document
  that holds the file and its dirty state, in `ByteDocument`'s shape rather
  than `TextDocument`'s.
- **AbydosApp**: `Editor/VboardPaneView.swift` (new): a web view on the board,
  a user script that watches the page's own socket for changes and presence,
  and a footer with the server, the encryption and *Copy link*. The route in
  `EditorViewController+Opening.swift`. The setting in the settings window.
- **Settings**: one string, the server address, empty by default.
- **Tests**: the client and the session against a stub HTTP server, answering
  with files exported by `vboard-local` 0.67.0 and checked into the test
  resources. A live round trip (private import, edit, export, delete) that
  starts a scratch `vboard-local` and runs only when one is found, in the same
  filter as `MermaidLiveTests` and `DrawioLiveTests`.
- **vboard**: nothing is required of it. Two things that would make the tab
  simpler are written in design.md as optional asks, not dependencies.
- **No `.abydos/backlog/spec` file is made untrue**: the backlog is retired.
