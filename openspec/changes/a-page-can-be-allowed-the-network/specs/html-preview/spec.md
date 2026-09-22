## MODIFIED Requirements

### Requirement: Nothing is fetched, and what was refused is said

No request from the pane SHALL leave this machine until somebody asks for it.
A reference to a remote address SHALL be refused — whether it is a navigation,
a subresource or a request a script makes — unless the document being shown has
been allowed.

Where the document itself names remote addresses, the pane SHALL say how many
it did not load and name the first, so a page that renders unstyled says why
rather than looking broken. The count SHALL be of the addresses written in the
document, and the pane SHALL NOT alter the document to count more exactly.

**Beside that sentence the pane SHALL offer to load them**, and pressing it
SHALL let that document fetch and show it again. The offer SHALL be about the
document rather than about the address named: a stylesheet at one host names
fonts at another, so allowing one address alone would leave the page unstyled
and the count wrong. An allowed page SHALL say that it is being fetched from
the network instead of saying what was refused, and SHALL offer to block it
again, which restores the refusal and forgets the allow.

A page in a repository is routinely full of CDN tags and tracking pixels, and a
preview that fetched them would make opening a file a network event. What that
costs is the case where the person reading the page wrote it — asked for on
2026-09-22 against a site's own index that had lost its typeface, one reference
short: "this is fine — but maybe it would be good to have a button to allow
it".

**A driven run SHALL fetch nothing whatever is remembered**, and SHALL say that
is why. A capture that reached somebody else's server would be a picture that
differs by network and a suite that fails on an aeroplane, which is the reason
`LinkOpener` refuses to open a browser on a driven run.

#### Scenario: a page built on a CDN

- **GIVEN** a page whose head links a stylesheet and two scripts at
  `https://cdn.jsdelivr.net/…`
- **WHEN** it is previewed with the machine online
- **THEN** none of the three is fetched, and the pane says three remote
  references were not loaded, names the first, and offers to load them

#### Scenario: a tracking pixel

- **GIVEN** a page carrying `<img src="https://…/pixel.gif">`
- **WHEN** it is previewed
- **THEN** no request is made for it

#### Scenario: allowing the page

- **GIVEN** a page whose only remote reference is a font stylesheet, refused
- **WHEN** the offer to load it is pressed
- **THEN** the page is shown again with the stylesheet and the fonts it names
  fetched, and the line says the page is being fetched from the network

#### Scenario: taking it back

- **GIVEN** that allowed page
- **WHEN** the offer to block it is pressed
- **THEN** the page is shown again with nothing fetched, the line says what was
  refused, and the file is no longer allowed

#### Scenario: a capture of an allowed page

- **GIVEN** an allowed file and a driven run
- **WHEN** the page is previewed
- **THEN** nothing is fetched and the pane says a driven run does not reach the
  network

## ADDED Requirements

### Requirement: An allowed page is remembered, per file, outside the project

An allow SHALL be kept for the file it was granted on, by that file's resolved
path, in this application's own support directory — never in the project. It
SHALL survive closing the file, the project and the application, so a page
somebody reads often stays as they left it.

Keeping it in the project would commit it: everyone who cloned the repository
would inherit permission for their machine to reach that server, which is the
shape of thing the pane's default exists to prevent, and it would put a line in
`git status` for reading a file. This is `project-trust`'s arrangement for
`project-trust`'s reason.

A file that is renamed or moved SHALL lose its allow and ask again, and a
driven run SHALL NOT write into the remembered list at all.

#### Scenario: reopening an allowed page

- **GIVEN** a page allowed yesterday
- **WHEN** the project is opened again and the file previewed
- **THEN** it is fetched without being asked for again

#### Scenario: nothing is written into the project

- **GIVEN** a project whose page has just been allowed
- **WHEN** `git status` is read
- **THEN** it names nothing that the allow wrote

#### Scenario: the file is renamed

- **GIVEN** an allowed page
- **WHEN** it is renamed and previewed
- **THEN** its references are refused and the offer to load them is made again

#### Scenario: a driven run leaves no trace

- **GIVEN** a driven run that allows a page
- **WHEN** it ends
- **THEN** the remembered list is as it was before the run
