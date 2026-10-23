## 1. What the page says, established first

- [x] 1.1 Against a scratch `vboard-local` (its own `--data` under the
  scratchpad, its own port, stopped by pid), confirm whether the client that
  makes a change receives its own `items` message. The design's dirty
  tracking depends on the answer. If it does not, the user script also notes
  the page's own mutating `fetch` calls, and the design says so.
- [x] 1.2 In the same run, confirm what a `presence` message holds for a
  private board with two browsers on it. The close prompt counts on it.
  (One entry per person, so others = entries − 1; recorded in design.md.)
- [x] 1.3 Export two fixture files from that server, a small board and one
  with an image, and check them into the test resources with the server
  version they came from. Add an encrypted one ("keep encrypted") for the
  refusal.

## 2. The client and the key

- [x] 2.1 `Vboard/VboardKey.swift`: 32 bytes from `SecRandomCopyBytes`,
  base64url without padding, and the private link built from a server URL, a
  board id and the key. It is never `Codable` and never logged. Its
  `description` is redacted so a stray interpolation cannot print it.
- [x] 2.2 `Vboard/VboardClient.swift`: `import(file:id:key:)` streamed with
  `URLSession.upload(fromFile:)`, `export(id:key:to:)` streamed to a file,
  `replace(file:id:key:)`, `delete(id:key:)`, `health()`. Every board request
  carries `X-Board-Key`, and cookies are taken from a cookie store it is
  given. It answers a typed outcome (created, replaced, refused with 409,
  signed out, unreachable, too large) rather than an HTTP status.
- [x] 2.3 `Vboard/VboardFile.swift`: from the first 4 KB of a file, whether it
  is a vboard board file, an empty one, an encrypted one, or neither, plus the
  size limit. This decides what is uploaded at all.
- [x] 2.4 `VboardClient.create(id:name:key:)`: a blank private temporary board
  for an empty file, named after the file without its extension.
- [x] 2.5 `VboardClientTests` against a stub HTTP server: the key in the
  header and never in a URL, a 409 on import retried once with a new id, a
  login redirect reported as signed out, export written through a temporary
  file, the fixtures accepted or refused as 2.3 says, and an empty or
  whitespace-only file created rather than imported.
- [x] 2.6 VboardClient.signedIn(): GET /api/v1/me/usage before any upload.

## 3. The document

- [x] 3.1 `Vboard/VboardDocument.swift`, in `ByteDocument`'s shape: the file
  URL, the board id, the key, a change count, and the count at the last save.
  Edited means they differ. A save takes the count when it starts and records
  it only if no change arrived before it finished.
- [x] 3.2 Never auto-saved: the auto-save pass skips it, as it skips a byte
  document. The close prompt and the edited dot read it as they read any
  document.
- [x] 3.3 The app's own write is recorded so the file watcher ignores it, and
  a change that is not the app's own is reported for the pane to act on.
- [x] 3.4 `VboardDocumentTests`: a change during a save keeps the document
  edited, a save with no change in flight clears it, and auto-save leaves it
  alone.

## 4. The tab

- [x] 4.1 The route: a `.vboard` goes to the board pane when `vboard.server`
  is set and the run is not driven. Otherwise it goes to the no-server notice,
  with *Open as text* for files under the text limit.
- [x] 4.2 `Editor/VboardPaneView.swift`: a `WKWebView` with a persistent
  `WKWebsiteDataStore(forIdentifier:)` per server origin. It loads the
  server's page first, waits for a session where there is a login, then
  imports and navigates to `/b/<id>#k=<key>`. Navigation outside the origin
  goes to `LinkOpener`, except the login's own round trip. Downloads go to
  Downloads.
- [x] 4.3 The user script: wraps `WebSocket` for this board's socket only and
  posts message types, the presence count and the page's own participant id.
  It sends nothing and touches no outgoing frame.
- [x] 4.4 The footer: the server's host, "encrypted on the server, readable by
  it while open", *Copy link*, and progress for upload and save.
- [x] 4.5 External change: replace under the same id and key, and on refusal
  delete and open again under a new id and key, saying the link changed. With
  unsaved changes, leave the board alone, as a dirty text tab is left alone,
  and say so once in the footer.
- [x] 4.6 Close: the unsaved-changes prompt, then, with others on the board,
  *End session* / *Leave it running* / *Cancel*. End session deletes, waits up
  to two seconds for the page to hear `deleted`, then tears down.
- [x] 4.7 `deleted` from somebody else, `accessRevoked` and an unreachable
  server each leave the tab saying what happened. Unsaved changes are kept in
  the last state the tab could save. Nothing is written to the file on its
  own.

## 5. The setting

- [x] 5.1 `vboard.server` in `Settings`, empty by default, with a description
  that says a file opened as a board is uploaded to that server. It is found
  by settings search under "vboard" and "board".
- [x] 5.2 `VboardServerAddress`: the setting as typed, judged where the tab
  asks. A value that is not an `http`/`https` server address makes the tab say
  why, in place of opening. Plain `http` to anything but loopback opens, and
  the footer says the board key travels unencrypted. (Not refused in the
  field: the settings window has no place for a reason, and a field that drops
  what was typed is worse.)

## 6. Checking it

- [x] 6.1 `VboardLiveTests`, in the same filter as `MermaidLiveTests` and
  `DrawioLiveTests`. When `vboard-local` is on the `PATH`, the test starts one
  on a scratch data directory and a free port. It imports a fixture
  privately, sees a 404 without the key, adds an item over REST, exports, and
  finds the item and the original ids in the file, then deletes and stops
  the server by pid. Without `vboard-local` it is skipped, and says so.
- [x] 6.2 Driven against a scratch project with a server named: the tab shows
  the driven-run sentence and the run makes no request. The pane's report
  says which state it is in.
- [ ] 6.3 By hand, once, against the hosted instance: sign in in the tab, open
  a fixture, copy the link, join from a browser signed in as somebody else,
  add a sticky there, see the dot, ⌘S, close with the other browser still on
  the board, end the session, and see the other browser lose the board. This
  is the claim no suite may make, because the suite may not reach that server.

## 7. Finishing

- [x] 7.1 `docs/release-notes-<version>.md`: one `##` for vboard boards in a
  tab, saying it needs a vboard server and what it sends there.
- [x] 7.2 The open questions in `design.md` that 1.1, 1.2 and 6.3 answer are
  answered there, and the ones still open stay listed.
- [ ] 7.3 `make test` and `make warnings`, both clean, exit codes read rather
  than output skimmed. Any file that grew past its recorded size has its
  record bumped in the same change.

## Notes

No `.abydos/backlog/spec/*.md` file is made untrue: the backlog is retired. No
capability in `openspec/specs` changes. `vboard-files` is new.
