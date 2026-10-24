## Context

A `.vboard` is vboard's board file: `{"format":"vboard","version":1,
"exportedAt","app","board":{name, contentRev, lastChangeAt, lineage},
"items","entries","assets"}`, written by the server as one line of JSON, with
every image, PDF and video on the board embedded as base64. A board with a
recorded workshop on it is hundreds of megabytes, and vboard's own limit is
700 MB.

The intended use is a **hosted** vboard instance, shared by a team and behind
its login. A file is put there for the length of a session, encrypted, so
colleagues can work on it with the person who opened it. Then it goes back
into the file and off the server.

Everything this change does to a board goes through vboard's documented REST
API (`docs/API.md` in vboard's repository, sections *Private boards*,
*Temporary boards*, *Board files* and *WebSocket*) and through its web app.
Nothing reads vboard's source, links its code or carries its files. These
calls were tried against `vboard-local` 0.67.0 on 2026-10-23, the same server
program the hosted instance runs, in a scratch data directory on a port of its
own:

| Call | What it did |
| --- | --- |
| `POST /api/v1/boards/import?temporary=true` | a new board, **every item with a new id**, `contentRev` reset to 0 |
| `POST …/import?temporary=true&id=b_<16 hex>` | the board under that id, **the file's item ids kept**, the file's marker kept |
| the same with `X-Board-Key: <43 chars>` | `201`, `private: true`, `temporary: true`, item ids kept |
| `GET /boards/{id}` without the key, or with a wrong one | `404`, as for an id that does not exist |
| a word from a sticky, searched for in the server's database file | not found |
| `GET …/export.vboard` with the key | the file in plain form, as edited |
| any of the imports, with an item id already used on that server | that item remapped to a new id, the rest kept |
| `POST …/import?temporary=true&id=<existing>` with a newer marker | `200 {"replaced": true}`: the content swapped in place |
| `DELETE /boards/{id}` with the key | `204` |

What vboard says about private boards, and this design repeats rather than
improves on: the content is encrypted at rest with a key the server never
stores. While anybody has the board open, the server holds the unwrapped key
in memory and works on plain data. "Not covered: a compromised running server,
people who have the link."

Abydos already has three pieces this is built from:

- **`DrawioEditor`**: a web view editing a file the app owns. Changes come out
  of the page, external writes go back in, and undo stays the page's own.
- **`ByteDocument`** (`hex-editor`): a document that is not text, has an
  edited dot and a close prompt, is saved on ⌘S through a temporary file, and
  is never auto-saved.
- **`LinkOpener` and the HTML preview's driven-run rule**: a driven run
  reaches no network.

The constraint is the one in the request: vboard is not publicly available, so
**no part of Abydos may need it**. That means it is not a build input, not a
test input, not a default, and no internal hostname may appear in this
repository.

## Goals / Non-Goals

**Goals:**

- Open a `.vboard` from the project tree and be on a private board on the
  team's server, with the link to give colleagues one click away.
- Start a board by making an empty `.vboard`, without visiting the server's
  start page first.
- ⌘S puts what is on the board, everyone's edits included, back into that same
  file. The edited dot and the close prompt mean what they mean everywhere
  else.
- When the session ends, the board is gone from the server.
- A machine with no server named behaves exactly as today, plus one sentence.

**Non-Goals:**

- **Opening a board that lives on the server**, with no file. The file is the
  document. The server is where it is worked on for a while. Asked for the next
  day and taken up in `a-server-board-opens-live-in-a-tab`.
- **Encrypted board files.** A file exported with "keep encrypted" needs the
  key of the board it came from to import. The tab says it cannot open one and
  offers the text.
- **Abydos's own server.** No `vboard-local` is started. Somebody who wants
  one runs it and names `http://localhost:7480`. Ruled out below.
- **Inviting people from Abydos.** The link is copied. vboard's own share
  dialog in the page (grants, password) is there for anything more.
- **A `.vboard` diff.** See *Open questions*.

## Decisions

### The server is a setting, and only a setting

`vboard.server`, a URL, empty by default, on a page of its own: Settings ▸
Tools ▸ vboard. With a value, that server is used. Without one, a `.vboard`
says that opening a board needs a vboard server, where to name it, and offers
the file as text, which is today's behaviour.

The setting is stored as typed and judged when a tab asks for it, by
`VboardServerAddress`:

- **Empty** is no server.
- **Not an `http` or `https` server address**: no scheme, another scheme, or a
  query, fragment or credentials in it. The tab says why, in place of opening,
  and nothing is sent.
- **Plain `http` to anything other than this machine** opens, and the footer
  says that the board's key crosses the network unencrypted. `http` to
  loopback is what a `vboard-local` somebody runs looks like, and says
  nothing.

It is not refused in the field. The settings window has no place for a reason,
and a field that drops what was typed is worse than a tab that says what is
wrong with it.

**Ruled out:**

- *Bundling the web app and server*, the way `Scripts/vendor-drawio.sh` does
  draw.io. vboard is not public. Its files may not be in a public repository
  or a public build.
- *A default address.* Every vboard server that exists is internal, and its
  hostname would then be in a public repository and sent to by everyone who
  opens a `.vboard`.
- *Starting `vboard-local` from the `PATH` when nothing is named.* That was
  the first draft of this design. It was dropped when the request was made
  precise: the point is a hosted instance colleagues can reach, and a board
  on loopback is one nobody else can join. Supervising a process (port, data
  directory, idle timeout, the user's own instance holding the lock on
  `~/.vboard`) would be machinery for the case the request is not about.
  `vboard-local` stays useful as a server somebody runs and names.
- *Falling back to another server when the named one does not answer.* A file
  meant for the team's server must not land somewhere else silently.

### The board is private, with a key made for the tab

On opening, Abydos makes a link key: 32 random bytes from `SecRandomCopyBytes`,
base64url without padding, 43 characters. It imports the file with that key:

    POST /api/v1/boards/import?temporary=true&id=b_<16 random hex>
    X-Board-Key: <key>
    <the file, streamed from disk>

The key goes only into the `X-Board-Key` header of Abydos's own requests and
into the fragment of the URL the web view loads. A browser never sends a
fragment, so neither reaches a request line or an access log. vboard refuses
a key in a query string with `400`. The key is held in
memory for the tab's lifetime and is not written to disk, settings or the
Keychain by Abydos.

The web app, once it has the link, adds the board to its list of known private
boards in the web view's data store. It does that for every private link it
opens. Abydos cannot remove that entry without reaching into vboard's storage,
and does not try. The board is deleted when the session ends, and a key to a
deleted board opens nothing.

**Ruled out:**

- *A plain temporary board.* Unlisted is not private. The board is reachable
  by id, its contents sit in the server's database in the clear, and an admin
  or a backup sees them. The request says encrypted.
- *Keeping the key so a restarted Abydos rejoins the same board.* It would
  make the key a secret on disk with a lifetime of its own. The session ends
  when the tab does. See *Open questions*.
- *Building the key material (`seal`) in Abydos, so the link key never reaches
  the server at all.* vboard's import takes the link key, not a seal, and
  "Importing an encrypted `.vboard` file still needs the link key". The
  server sees the key in the request and, by its documentation, never stores
  it.

### A fresh board id, so the file's items keep theirs

The `id` parameter exists for restoring a browser's backup. It is used here
because it is the import that keeps item and entry ids and the file's marker.
A plain import gave every item a new id on every open: the item `i_4f0c…` came
back as `i_64ae…`. A board whose identities change each time it is opened
cannot be compared with itself, and it would make the replace-in-place below
compare markers that mean nothing. A `409` (the id exists) is retried once
with another id.

Two things the server does that the tab accepts:

- An item id already in use on that server, because the same file is open
  twice or somebody imported it permanently, is remapped. That item gets a new
  id in the saved file.
- The import sets every item's `boardId` to the board's id and its
  `updatedAt` to now. The saved file carries those values.

A file over 700 MB, not `format: "vboard"`, or encrypted (vboard's encrypted
format marker within its first 4 KB) is not uploaded. The tab says which, and
offers the text where the file is small enough to show as text.

### An empty file is a new board

A file that is empty or holds only whitespace is not imported. There is
nothing to import. Instead it is created:

    POST /api/v1/boards
    {"id": "b_<16 random hex>", "name": "<file name without extension>",
     "temporary": true, "private": true, "key": "<key>"}

Tried against `vboard-local` 0.67.0: `201`, `private: true`, `temporary:
true`, a `404` without the key, and an export of `{"format":"vboard", …,
"items":[],"entries":[],"assets":[]}`. The tab opens unedited, because nothing
differs from the file yet in any way a save would preserve. The first change
marks it, and the first ⌘S gives the file its contents.

The key goes in the body here, where vboard's create endpoint takes it, and
not in a header. That is vboard's documented place for it on this call. It is
still never in a URL.

**Ruled out:** writing a minimal board file into the empty file on open, so
the ordinary import path could take it. Opening a file would then change it,
and the project's diff would show a file nobody had saved.

### A provisional or restored tab waits to be asked

A `.vboard` opened as a provisional tab, by a single click or by arrowing
through the project tree, uploads nothing. Nor does one brought back by a
restored session. The tab shows "Open <file> as a board on <host>?" with
*Open on <host>* and *Open as Text*, and the board is started only when
somebody presses the button or commits to the tab by opening it for real.

This is the `previews` capability's rule that a preview nobody has looked at
costs nothing. Here the cost is a file sent to a shared server. Arrowing
through a folder of boards must not upload each one of them, and relaunching
the app must not upload the files somebody opened yesterday.

### The tab is vboard's web app, signed in through its own login

`WKWebView` on `<server>/b/<id>#k=<key>`. Navigation outside the server's
origin is cancelled and handed to `LinkOpener`, except the server's own login
redirects to its identity provider, which stay in the view until they come
back. Downloads the page offers, such as its own ".vboard herunterladen" or
exports, go to the Downloads folder as a browser's would, not into the project.

**Signing in**: the web view uses a persistent `WKWebsiteDataStore(forIdentifier:)`
for that server's origin, so the user signs in once, in the tab, through the
server's own login page. The import, export and delete calls Abydos makes
natively carry the cookies of that store, read from its `httpCookieStore`
before each call, and the board key. No token is made or kept by Abydos.

So the order on opening is: load the server's page in the web view first. If
it lands on the login, the person signs in. Once a session cookie is there, do
the import, then navigate to the board. A server without a login skips
straight to the import.

**Signing in is asked before uploading.** Before the import, the tab asks
`GET /api/v1/me/usage`, the cheapest call that needs a person. A server without
a login answers `200` for its single local user (tried against `vboard-local`
0.67.0). A server with a login answers `401 auth.loginRequired` to anybody not
signed in (vboard's `registerUsage`). Without that question, an import made
while signed out sends the whole file, hundreds of megabytes for some boards,
only to be told `401` at the end of it.

**Ruled out:**

- *A personal access token and a localhost proxy*, which is how vboard's iPad
  app does it. That is a proxy server inside Abydos, rewriting a page's origin.
  It works for the iPad because there the page *must* be on localhost for
  service workers. Here nothing needs that, and a proxy would also see every
  board key.
- *Doing the import and export in the page*, with `evaluateJavaScript` and
  `fetch`. The body crosses the bridge as a string, and a 300 MB board is a
  300 MB string, twice.

### Sharing is the board's private link, copied

The footer has *Copy link*, which puts `<server>/b/<id>#k=<key>` on the
clipboard. That is all Abydos adds. Whoever opens the link must still be able
to sign in to the server, where it has a login. The key opens the board, not
the server. The page's own share dialog stays available in the tab for
grants and a password, and vboard keeps those working on a private board.

The footer says, in one line: the server's host, that the board is encrypted
there, and that the server can read it while it is open. The setting's help
text says that a file opened as a board is uploaded to that server.

### Changes and people are seen on the page's own socket

A `WKUserScript` at document start wraps `window.WebSocket`. For the one
socket whose URL is `/api/v1/boards/<this id>/ws`, it posts to a script message
handler:

- the `type` of each incoming message. `items`, `entries` and `board` after
  the snapshot mark the document edited, whoever caused them.
- the number of entries in the snapshot's and each later `presence` list, so
  the tab knows how many *other* people are on the board.
- `deleted`, `replaced` and `accessRevoked`, which the pane acts on.

Nothing else is forwarded, and nothing is sent. This relies on the WebSocket
protocol vboard documents, not on anything inside its web app. It wraps the
browser's `WebSocket` and reads JSON frames. The private board's
`{"type":"auth","key":…}` that the page sends is outgoing and is not touched.

**Ruled out:**

- *A second WebSocket from Abydos.* Every socket is a participant. The board
  would show an "Abydos" avatar beside the person using it, on their screen
  and their colleagues' screens.
- *Polling the export.* Every poll would build the whole file, assets
  included.
- *Polling `GET /boards/{id}`.* It answers with every item.

**Established** against `vboard-local` 0.67.0, with two sockets on one
private board: the client that makes a change gets its own `items` message
back, with `origin` set to its own `connId`. So the socket alone sees every
change, and the page's `fetch` calls need not be watched. `presence` has one
entry per *person*, not per socket. With a login, the server replaces the
participant id a page sends with the signed-in user's id, so two tabs of one
person are one entry. The tab's own person is always in the list while its
socket is open, so "others on the board" is the length of the list minus one.
The page's own participant id is not needed.

### The page does not keep the board in the account

With a login, vboard's page "keeps" every private link it opens: it wraps
the board's key to the person's own key pair (`POST /boards/{id}/my-slot`),
and when they have none it offers to set one up with a passkey. An embedded
`WKWebView` cannot use passkeys, and a board that ends when its tab closes
has nothing to keep. Reported on 2026-10-23 after trying it against the
hosted instance.

A second user script wraps `window.fetch` and answers that one call, for
the board in the page's own address, with a 403. vboard's page takes any
refusal other than 409 as "not kept" and says nothing (`claimSlot` in its
`api/boardDek.ts`). The endpoint is documented, so this relies on the API,
as the socket watcher does. The live test checks the 403 against the real
page and that other requests pass. (`vboard-local` itself answers 404 there,
so the 403 can only have come from the script.)

**Better, and not this repository's to make:** vboard's page not claiming a
slot for temporary boards at all. Asked of vboard as an optional change; the
wrapper stays until every server has it.

### The page starts loading while the file goes up

The web app is loaded out of sight as soon as the tab connects, before the
sign-in check and the upload, so its scripts are cached by the time the board
exists. Reported on 2026-10-23 as "a bit slow to open the document": the page
had waited for both round trips before it started.

### Saving writes the server's bytes, through a temporary file

⌘S starts `GET …/export.vboard` with the key, streamed to a temporary file
beside the original, which is then renamed over it. The write is recorded as
the app's own so the file watcher does not take it for somebody else's.

The document stays edited if a change message arrived after the export was
asked for. A count of change messages is taken when the save starts and
compared when it ends. With colleagues moving things, ⌘S never clears the dot
over a change the file does not have.

**Never auto-saved.** It is a `ByteDocument` decision for a different reason:
an export is a round trip to a server that may be slow or gone, and auto-save
fires on losing focus.

**Ruled out:** writing a stable, indented layout (one item per line) so that
`git diff` shows the edit. Abydos would then be choosing the layout of
somebody else's format. A file saved by vboard's own download would flip back
to one line, and every save from the other place would be a whole-file diff.
See *Open questions*.

### Somebody else writing the file replaces the board, or opens it again

The watcher's change (not one recorded as the app's own) goes to the server
as `POST …/import?temporary=true&id=<this id>` with the key. A
`200 replaced` makes the page reload itself, because the server closes its
socket with `replaced`, and colleagues' pages reload the same way. Anything
else (a `409` because the file's marker is not newer, which a hand-edited file
or a `git checkout` of an older one will be) deletes this board and opens the
file again under a fresh id and a fresh key. The tab says the link changed,
since the one colleagues have now opens nothing.

**Unsaved changes on the board when the file changes underneath** are the text
editor's case, and the text editor does not ask: it leaves a buffer with
unsaved edits alone. So the board is left as it is, and the tab's footer says,
once, that the file changed on disk and that ⌘S writes the board over it.
Asking was the first draft. It would have made a board tab the one kind of tab
that interrupts somebody for a write they did not make.

The web app's own undo history is gone after either path. `DrawioEditor`
makes the same trade, and says so.

### Closing ends the session, and asks when others are on the board

Closing a board tab with unsaved changes asks, as every tab does. Then, when
the socket's presence counts anybody other than the page itself, it asks
again: "2 others are on this board. Closing it ends the session for them."
The choices are *End session*, *Leave it running* and *Cancel*.

- **End session** sends `DELETE /api/v1/boards/{id}` with the key, waits up to
  two seconds for the page's socket to report `deleted`, then tears the web
  view down. The order matters. The web app drops its local backup of a
  temporary board only when it hears `deleted` with reason `"deleted"`. A web
  view torn down first would keep a backup, encrypted with the link key, in
  that store, and offer it under "Temporary boards" the next time anything
  opens that server. Colleagues' pages hear `deleted` too and leave the
  board.
- **Leave it running** tears the view down and forgets the board. It stays on
  the server as long as anybody is on it, and the server deletes it after its
  grace period (seven days by default) once nobody is. The choice says that
  edits made from then on will not reach the file.

A delete that fails (server gone, app quit) is left to the server's own
cleanup of temporary boards. The tab does not retry.

**Closing stays synchronous.** The editor's close paths, closing all tabs and
swapping the project, are synchronous and loop until the tabs are gone. A
board tab's close that returned and finished later would be closed again by
the next turn of that loop. So the close runs its prompts as modal alerts and
waits for the save and the delete by turning the main run loop with a
deadline, the same technique the HTML and draw.io panes use for
`takeSnapshot`.

A tab that goes without being asked, because its window closed or its
provisional slot was reused, ends its board in the background. The pane is
kept alive off screen until its page hears `deleted` or two seconds pass, so
vboard's page still drops its backup.

### A driven run never reaches a server

`DrivenRun.isActive` puts the tab in the *no server* state whatever the
setting says. It says that a driven run does not reach a server, as the HTML
preview says it. A capture that depended on a server would differ by machine,
and a scratch file sent to the team's real server is the kind of mistake the
house rules exist for.

## Risks / Trade-offs

- **[The server reads the board while it is open]** → that is vboard's model
  of a private board, not something Abydos can improve. The footer says it
  in so many words, so "encrypted" is not read as "end-to-end".
- **[The link is the key]** → anybody the link is forwarded to, who can sign
  in to the server, is on the board. vboard's page can set a password or
  rotate the key, and the session ends when the tab closes.
- **[An SSO login that refuses an embedded web view]** → some identity
  providers block `WKWebView`. Not seen yet, because the only login tried is
  vboard's local test provider. See *Open questions*.
- **[A colleague's edit after the last save is lost on close]** → the close
  prompt counts unsaved changes from everyone, so a session with colleagues
  still typing asks before it discards anything.
- **[vboard changes its API]** → the calls used are the documented, versioned
  `/api/v1`, and vboard has kept old clients working through every documented
  change (`docs/API.md` marks each with the version that made it). The live
  test catches a break on any machine with `vboard-local`.
- **[A large board is slow to open and to save]** → upload and export are
  streamed, never held as a string. The pane says "Uploading 214 MB…" and
  "Saving…" with progress from the request, rather than a frozen tab.
- **[A web view with a session in it]** → the data store is per server
  origin and used by board tabs only. Signing out is the server's own sign-out
  in the page.

## Open questions

- **Rejoining after a restart.** Abydos quitting with a board tab open ends
  the session the way a failed delete does: the board lingers until the
  server's grace period, and the reopened tab makes a new board with a new
  link. Keeping the key per file in the Keychain would let it rejoin. It would
  also make the key a stored secret. Not chosen until somebody misses it.
- **How `.vboard` changes should read in a diff.** The file is one line, so
  `git diff` and Abydos's file diff both say only that it changed. Options, not
  chosen: a `.vboard`-aware diff in Abydos (items by id: added, removed,
  changed fields), which owns nothing of the format; or asking vboard for an
  export layout with one item per line, which would have to become vboard's
  own default for files to stay stable. Either is a change of its own.
- **The oldest server to accept.** Private boards are from vboard 0.7.0,
  import under an id and the content marker from 0.6.0. Only 0.67.0 has been
  tried. The `version` in the socket's snapshot and the export's `app` field
  are where a minimum would be checked.
- **SSO in an embedded web view.** If the hosted server's login refuses
  `WKWebView`, the fallback is `ASWebAuthenticationSession` to the server's
  `/auth/app-login`, as the iPad app does. That returns a token by redirecting
  to `vboard://…`, a scheme Abydos would have to register or vboard would have
  to make configurable. Not designed until the server needs it.
- **Two things vboard could offer that would make this simpler**, neither
  required: an import flag that keeps ids without the restore semantics (no
  `410` after a recent delete, no marker comparison), and a way for an
  embedding app to learn "the board changed" and "who is here" without
  wrapping the page's socket, such as the existing `window.vboardApp` bridge
  growing a callback.
