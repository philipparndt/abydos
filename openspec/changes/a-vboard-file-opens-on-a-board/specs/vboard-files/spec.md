## ADDED Requirements

### Requirement: A vboard file opens as a private temporary board on the server named in the settings

When the `vboard.server` setting names a server, opening a `.vboard` file SHALL
show it as a board in that server's own web app. The board SHALL be made by
importing the file as a **temporary, private** board, under a newly generated
board id and encrypted with a newly generated link key. The file SHALL be
streamed from disk rather than read into memory as text.

The link key SHALL be 32 random bytes, made for that tab and no other. It SHALL
be sent only in the `X-Board-Key` header of Abydos's own requests and in the
fragment of the URL the tab loads. Abydos SHALL NOT write it to disk, the
settings or the Keychain.

Private because the request is for the file to be hosted encrypted: a merely
unlisted board sits in the server's database in the clear. A fresh board id
because the import that takes an id is the one that keeps the file's item ids.
A plain import gave every item a new id on every open (`i_4f0c…` came back as
`i_64ae…` against `vboard-local` 0.67.0), and a board whose identities change
each time it is opened cannot be compared with itself.

#### Scenario: a server is named

- **GIVEN** `vboard.server` set to a reachable vboard server and the person
  signed in to it
- **WHEN** a `.vboard` is opened from the project tree
- **THEN** the tab shows a board on that server holding the file's items under
  the ids they have in the file, and the server reports it as private and
  temporary

#### Scenario: the board without its key

- **GIVEN** a `.vboard` open as a board
- **WHEN** anybody asks the server for that board id without the key, or with
  another key
- **THEN** the server answers that there is no such board

#### Scenario: a server with a login, not yet signed in

- **GIVEN** `vboard.server` set to a server with a login and no session in the
  tab's web data store
- **WHEN** a `.vboard` is opened
- **THEN** the tab shows the server's login, nothing is uploaded until the
  person has signed in, and the board appears afterwards

#### Scenario: the same file opened twice

- **GIVEN** a `.vboard` already open in one tab
- **WHEN** it is opened in a second window
- **THEN** both show a board, each with its own key, and the second board's
  items, whose ids the server already has, are given new ids by the server and
  not refused

### Requirement: A provisional or restored tab uploads nothing until somebody asks

A provisional or restored board tab SHALL NOT upload anything: neither a
`.vboard` opened as a provisional tab, by a single click or by arrowing
through the project tree, nor one brought back by a restored session. It SHALL
show "Open <file> as a board on <host>?" with an
*Open on <host>* button and *Open as Text*, and SHALL start the board only
when somebody presses that button or commits to the tab by opening it for
real.

A preview nobody has looked at costs nothing, as the `previews` capability
says, and here the cost is a file sent to a shared server. Arrowing through a
folder of boards must not upload each one, and relaunching the app must not
upload the files somebody opened yesterday.

#### Scenario: arrowing through a folder of boards

- **GIVEN** `vboard.server` set and a folder of `.vboard` files
- **WHEN** the selection is moved through them with the arrow keys
- **THEN** each provisional tab asks whether to open the file as a board on
  that host, and no request is made to the server

#### Scenario: a restored session

- **GIVEN** a `.vboard` that was open as a board when the app quit
- **WHEN** the app is started again and restores that tab
- **THEN** the tab asks whether to open the file as a board, and nothing is
  uploaded until *Open on <host>* is pressed

#### Scenario: committing to the tab

- **GIVEN** a provisional tab asking whether to open a `.vboard` as a board
- **WHEN** the file is double-clicked in the project tree
- **THEN** the board is started as if *Open on <host>* had been pressed

### Requirement: The server address is judged when a tab asks for it

The `vboard.server` setting SHALL be stored as typed, on its own page,
Settings ▸ Tools ▸ vboard, and judged when a tab asks for it. Empty SHALL mean
no server. A value that is not an `http` or `https` server address, because it
has no scheme, another scheme, or a query, fragment or credentials, SHALL make
the tab say why in place of opening, and nothing SHALL be sent. Plain `http`
to anything other than this machine SHALL open, and the tab's footer SHALL say
that the board's key crosses the network unencrypted.

The value is not refused in the field: the settings window has no place for a
reason, and a field that drops what was typed is worse.

#### Scenario: an address with no scheme

- **GIVEN** `vboard.server` set to `boards.example.org`
- **WHEN** a `.vboard` is opened
- **THEN** the tab says the setting is not an `http` or `https` server address,
  and no request is made

#### Scenario: plain http to another machine

- **GIVEN** `vboard.server` set to `http://boards.example.org`
- **WHEN** a `.vboard` is opened as a board
- **THEN** the board opens, and the footer says the board's key crosses the
  network unencrypted

### Requirement: An empty vboard file opens as a new blank board

A `.vboard` file SHALL open as a new blank board when it is empty or holds
nothing but whitespace. The board SHALL be private and temporary, made under a
generated id with a generated key like any other, and named after the file
without its extension. The first ⌘S SHALL write the board into the file.

Asked for on 2026-10-23: "it should be possible to also open a empty vboard
file (create a blank file "my.vboard") to create a new document". A file of
nothing is not a board file, and refusing it would make the only way to start
a board a trip to the server's own start page and a download.

#### Scenario: a touched file

- **GIVEN** `vboard.server` set and an empty file `my.vboard` made in the
  project tree
- **WHEN** it is opened
- **THEN** the tab shows a blank board named `my`, the file on disk is still
  empty, and the tab is not edited

#### Scenario: the first save

- **GIVEN** that blank board with a sticky added
- **WHEN** ⌘S is pressed
- **THEN** the file holds a vboard board file named `my` with the sticky in it

### Requirement: A board tab can be shared with its link

A board tab SHALL offer *Copy link*, which SHALL put the board's private link
(the server's board address with the key in its fragment) on the clipboard.
Somebody who opens that link, and can sign in to the server where it has a
login, SHALL be on the same board, and their changes SHALL reach the tab as
they make them.

#### Scenario: a colleague joins

- **GIVEN** a `.vboard` open as a board, and its link copied and sent
- **WHEN** a colleague opens the link in a browser and adds a sticky
- **THEN** the sticky appears in the tab, and the tab shows the edited dot

### Requirement: The tab says where the file is and what that means

A board tab SHALL say, for as long as it is open, the host of the server the
file was sent to, that the board is encrypted there, and that the server can
read it while somebody has it open. The `vboard.server` setting's description
SHALL say that a file opened as a board is uploaded to that server.

"Encrypted" alone would be read as end-to-end, and it is not. vboard holds a
private board's content key in memory while it is open and works on plain
data, and says so in its own documentation.

#### Scenario: a named server

- **GIVEN** `vboard.server` set to `https://boards.example.org`
- **WHEN** a `.vboard` is open as a board
- **THEN** the tab's footer names `boards.example.org`, says the board is
  encrypted there, and says the server can read it while it is open

### Requirement: Without a server, a vboard file says how to get one and is still readable

When no server is named, a `.vboard` SHALL open showing no board. It SHALL say
that opening a board needs a vboard server and where to name one. It SHALL
offer to open the file as text, which is how a `.vboard` opened before this
change. When the named server does not answer, the tab SHALL say so and offer
the text, and SHALL NOT send the file anywhere else.

Nothing about vboard SHALL be required for Abydos to build, start, pass its
tests or open any other file. vboard is not publicly available: no part of it
SHALL be bundled, and no default server address SHALL be in the program or in
this repository.

#### Scenario: no server named

- **GIVEN** `vboard.server` empty
- **WHEN** a `.vboard` is opened
- **THEN** the tab says a vboard server is needed and names the setting, offers
  to show the file as text, and no network request is made

#### Scenario: the server named is not answering

- **GIVEN** `vboard.server` set to an address nothing answers on
- **WHEN** a `.vboard` is opened
- **THEN** the tab says that server cannot be reached and offers the text

### Requirement: A board opened from a file is not kept in the account

The tab's page SHALL NOT keep its board in the signed-in person's account: its
own request to do so (`POST /api/v1/boards/{id}/my-slot` for the board it
shows) SHALL be answered in the page with a refusal, and SHALL NOT reach the
server. No other request SHALL be touched.

With a login, vboard's page keeps every private link it opens by wrapping the
board's key to the person's own key pair, and offers to set one up — with a
passkey — when there is none. Seen on 2026-10-23: "it was asking for a
passkey which is not possible in our integration but should also not be
necessary for ephemeral/local boards". A board that ends with its tab has
nothing to keep.

#### Scenario: signed in without a key of one's own

- **GIVEN** a server with a login, a person signed in who has never set up a
  key, and a `.vboard` opened as a board
- **WHEN** the board has loaded
- **THEN** the page asks for no passkey and offers no key set-up, and the
  server holds no slot for that board

### Requirement: Changes on the board are the tab's unsaved changes, saved on ⌘S and never on their own

A change to the board's items, widget entries or name SHALL mark the tab
edited as soon as it is made, whether the person at the tab made it or
somebody else on the board did. ⌘S SHALL write the server's export of the
board into the file, through a temporary file beside it renamed into place,
and SHALL record the write as the app's own. The edited mark SHALL go only if
no change arrived while the save was in flight. A board tab SHALL NOT be
auto-saved, whatever the auto-save setting says.

Changes SHALL be learnt from the page's own connection to the board, not from
a connection of Abydos's own, because every connection to a board is a
participant everybody on it can see.

The export SHALL be written as the server gives it. Abydos does not own the
format and SHALL NOT rearrange it.

#### Scenario: a sticky added and saved

- **GIVEN** a `.vboard` open as a board
- **WHEN** a sticky is added on the board and ⌘S is pressed
- **THEN** the tab shows the edited dot from the moment the sticky appears,
  the file on disk afterwards holds the sticky in plain form, and the dot is
  gone

#### Scenario: auto-save on, board edited

- **GIVEN** auto-save on and an edit on the board
- **WHEN** the auto-save interval passes and the window loses focus
- **THEN** the file on disk is unchanged and the tab still shows the dot

#### Scenario: a colleague's edit while saving

- **GIVEN** ⌘S pressed on an edited board
- **WHEN** a colleague moves an item before the save finishes
- **THEN** the save completes and the tab still shows the dot

#### Scenario: no Abydos participant

- **GIVEN** a `.vboard` open as a board and shared
- **WHEN** a colleague looks at who is on the board
- **THEN** the people listed are the ones looking at it, and Abydos is not
  among them

### Requirement: Closing the tab ends the session, and asks first when others are on the board

Closing a board tab with unsaved changes SHALL ask, as a text tab asks. When
anybody other than the tab itself is on the board, closing SHALL then say how
many and ask whether to end the session for them, leave the board running, or
cancel.

Ending the session SHALL delete the board from the server before the tab's
web view is torn down, so the web app hears the delete and keeps no backup of
it. Leaving it running SHALL tear the view down without deleting, and SHALL
have said that edits made from then on will not reach the file. A delete that
fails SHALL be left to the server's own cleanup of temporary boards.

#### Scenario: alone on the board

- **GIVEN** a `.vboard` open as a board, saved, with nobody else on it
- **WHEN** the tab is closed
- **THEN** nothing is asked, and the board no longer exists on the server

#### Scenario: colleagues still on the board

- **GIVEN** a saved board with two colleagues on it
- **WHEN** the tab is closed
- **THEN** the tab says two others are on the board and asks, and choosing to
  end the session deletes the board and takes it away from their browsers

#### Scenario: leaving it running

- **GIVEN** the same question
- **WHEN** *Leave it running* is chosen
- **THEN** the tab closes, the board is still on the server for the
  colleagues, and the choice had said their further edits will not reach the
  file

### Requirement: A file changed by somebody else is put back on the board

The board SHALL be replaced, when the file changes on disk and the change is
not the app's own write, with the file's content under the same board id and
key if the server accepts that. Otherwise the board SHALL be deleted and the
file opened again under a new id and key, and the tab SHALL say that the
board's link has changed.

With unsaved changes on the board, the board SHALL be left as it is, as a text
tab with unsaved edits is left alone, and the tab's footer SHALL say once that
the file changed on disk and that ⌘S writes the board over it. A text tab does
not ask about a write it did not make, and a board tab SHALL NOT be the one
kind of tab that does.

#### Scenario: a checkout of an older version

- **GIVEN** a `.vboard` open as a board with no unsaved changes
- **WHEN** `git checkout` puts an older version of the file in place
- **THEN** the board shows the older version's items, and the tab says the
  link has changed

#### Scenario: a change on disk while the board has unsaved changes

- **GIVEN** a `.vboard` open as a board with a sticky added and not saved
- **WHEN** another program writes the file
- **THEN** the board keeps the sticky and is not reloaded, nothing is asked,
  and the footer says once that the file changed on disk and that ⌘S writes
  the board over it

#### Scenario: the tab's own save

- **GIVEN** a `.vboard` open as a board
- **WHEN** ⌘S writes the file
- **THEN** the board is not reloaded

### Requirement: A file the server cannot take is not sent

A file SHALL NOT be uploaded when it is not a vboard board file, when it is
already encrypted with a board's link key, or when it is larger than the
server accepts. The tab SHALL say which of the three it is and SHALL offer the text
where the file is small enough to be shown as text.

#### Scenario: an encrypted board file

- **GIVEN** a `.vboard` exported from a private board with "keep encrypted"
- **WHEN** it is opened
- **THEN** nothing is uploaded, and the tab says encrypted board files cannot
  be opened as a board

### Requirement: A driven run never reaches a vboard server

On a driven run a `.vboard` SHALL open in the no-server state whatever the
setting says. It SHALL say that a driven run does not reach a server, and SHALL
make no request.

A capture that depended on a server would differ from machine to machine, and
a driven run's scratch file sent to the team's real server is the kind of
mistake the house rules exist for.

#### Scenario: a driven run with a server named

- **GIVEN** `vboard.server` set and a driven run opening a `.vboard`
- **WHEN** the tab appears
- **THEN** it says a driven run does not reach a server, and no request was
  made to that server
