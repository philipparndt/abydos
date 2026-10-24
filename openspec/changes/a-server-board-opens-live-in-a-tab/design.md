## Context

A board tab today (`VboardPaneView`) has two halves. The front half reaches the
server: it decides between going direct and going through the signing proxy,
runs the system's sign-in sheet, makes the web view in the server's shared data
store, applies the theme and keeps links that leave the server out of the tab.
The back half is the file: import as a private temporary board, the dirty
count, the lease, ⌘S as an export, and deleting the board on close.

A live board needs the front half and none of the back.

## Goals / Non-Goals

**Goals:**

- Find a board on the server by typing part of its name, and open it in a tab.
- The tab is the board itself. Nothing in the tab suggests a file: no dot, no
  save prompt, no "kept for this session only".
- A copy can be written to disk on purpose.

**Non-Goals:**

- **Private boards.** Their names are sealed and they open only with their link
  key, which the server does not hand out. The listing leaves them out, as the
  server's own picker lookup does.
- **Restoring a live board tab with the session.** A page tab is not restored
  today; a live board is the same kind of tab.
- **Opening a pasted board link.** Possible later on the same pane.

## Decisions

### The listing is the server's picker lookup

`GET /api/v1/boards?q=<typed>&limit=100`: the boards the server's own overview
would list to this account, whose name contains the text, names starting with
it first, then newest update. It is filtered on the server so a large
installation is never loaded whole, and asked again as the text changes, a
moment after the last key.

Rejected: the plain listing (every board at once) and the paged overview (sorts
but does not filter by name).

### One pane, opened on a file or on a board id

`VboardPaneView` gains a source: a file, or a board id with its name. A board
id skips the file half entirely — no `VboardDocument` is made — and loads
`/b/<id>` once the connection is chosen. Closing it, from the close button or
the window, releases the proxy and nothing else: there is no session to end.

Rejected: a second pane class beside it. The front half is two thirds of the
file and would be copied whole.

To stay under the 1100-line limit, the web view's download, JavaScript dialog
and open-panel delegates — which touch none of the pane's private state — move
to `VboardPaneView+Dialogs.swift`.

### The tab is a page tab named by the board

`openPage` with the identifier `vboard/<host>/<board id>`: opening the same
board again brings its tab to the front, and the tab carries the board's name.

### The copy is the server's export

`VboardClient.export(id:into:)`, into a temporary beside the place chosen and
renamed, the way a file board's save writes. The save panel starts in the
project with the board's name.

## Risks / Trade-offs

- **Edits are immediate and shared.** That is what was asked for; the status
  bar says so ("live board: changes are everyone's") where a file board says it
  is kept for the session.
- **A server with a login** shows the picker only after a sign-in, since the
  listing is per account. The picker runs the same sign-in sheet first when it
  has no token.
