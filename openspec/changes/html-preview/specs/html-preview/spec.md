## ADDED Requirements

### Requirement: An HTML file is shown as the page it makes

A `.html`, `.htm` or `.xhtml` SHALL have a rendered form, and the tab bar's
preview control SHALL offer *Source*, *Preview*, *Split Right* and *Split Down*
for it, remembered across sessions and settable by `--preview-mode` as every
other previewed file's is. It SHALL open as its source, the way markdown does:
HTML is read as well as rendered, and a machine-written report of several
megabytes SHALL NOT be rendered because a tab was opened on it.

`.vue`, `.xml`, `.xsd`, `.xsl` and `.pom` SHALL NOT be previewed although they
are coloured by the same grammar — a component and a build file are not pages —
and `.svg` SHALL remain a picture.

Asked for 2026-09-22: "would be nice to have the same preview as for markdown
also for html docs".

#### Scenario: opening a page

- **GIVEN** a `docs/index.html`
- **WHEN** it is opened
- **THEN** it shows its source, and the tab bar offers all four modes

#### Scenario: the mode is remembered

- **GIVEN** that file shown as *Split Right*
- **WHEN** the project is closed and opened again
- **THEN** the file comes back as *Split Right*

#### Scenario: a Vue component is not a page

- **GIVEN** a `.vue`, a `.pom` and an `.svg`
- **WHEN** each is opened
- **THEN** the first two offer no preview, and the third opens as a picture

### Requirement: The page is the buffer, not the file on disk

The pane SHALL render what is in the editor, including unsaved work, and SHALL
follow it as it is typed, debounced so that a document half way through being
typed is not rendered between two characters. The page's scroll position SHALL
survive a re-render.

#### Scenario: typing in the source half

- **GIVEN** a page shown as *Split Right*, never saved since it was changed
- **WHEN** a heading's text is changed in the source
- **THEN** the pane shows the new text without the file being saved

#### Scenario: an edit near the end of a long page

- **GIVEN** a page of several screens, scrolled to the bottom
- **WHEN** a word is typed in the source
- **THEN** the pane is still at the bottom afterwards

### Requirement: What the page asks for is read from beside it, and nothing else

A relative stylesheet, script, picture or font SHALL be read off the disk under
the directory the file is in, so a page looks the way it looks in a browser. A
reference that climbs out of that directory, and one that names a file that is
not there, SHALL NOT be served.

The file's own directory rather than the project's root: a `docs/` folder's
page SHALL reach its own `style.css`, and no page SHALL be a way to read the
rest of the repository.

#### Scenario: a page with a stylesheet beside it

- **GIVEN** `docs/index.html` linking `style.css` and `<img src="img/logo.png">`
- **WHEN** it is previewed
- **THEN** the page is styled and the picture is shown

#### Scenario: a reference that climbs out

- **GIVEN** a page whose markup names `../../.ssh/id_rsa` as a script
- **WHEN** it is previewed
- **THEN** nothing is served for it and the page renders without it

### Requirement: Nothing is fetched, and what was refused is said

No request from the pane SHALL leave this machine. A reference to a remote
address SHALL be refused whether it is a navigation, a subresource or a request
a script makes.

Where the document itself names remote addresses, the pane SHALL say how many
it did not load and name the first, so a page that renders unstyled says why
rather than looking broken. The count SHALL be of the addresses written in the
document, and the pane SHALL NOT alter the document to count more exactly.

A page in a repository is routinely full of CDN tags and tracking pixels, and a
preview that fetched them would make opening a file a network event.

#### Scenario: a page built on a CDN

- **GIVEN** a page whose head links a stylesheet and two scripts at
  `https://cdn.jsdelivr.net/…`
- **WHEN** it is previewed with the machine online
- **THEN** none of the three is fetched, and the pane says three remote
  references were not loaded and names the first

#### Scenario: a tracking pixel

- **GIVEN** a page carrying `<img src="https://…/pixel.gif">`
- **WHEN** it is previewed
- **THEN** no request is made for it

### Requirement: A page's own scripts run only in a trusted project

While a project is untrusted the pane SHALL render the page with its scripts
disabled, and SHALL say so in the same words every other refusal uses, offering
the same one gesture that grants trust. In a trusted project scripts SHALL run.

A page's `<script>` is the project's code, and *project-trust* holds that an
untrusted project executes nothing of its own. The previews this application
renders itself are unaffected by trust; this is the one preview that would run
something the project wrote.

#### Scenario: previewing a page in an untrusted project

- **GIVEN** a just-cloned project nobody has trusted, holding a coverage report
- **WHEN** the report is previewed
- **THEN** it renders as markup alone, its scripts having not run, and the pane
  says the project is not trusted and offers to trust it

#### Scenario: trusting the project

- **GIVEN** that pane
- **WHEN** trust is granted from it
- **THEN** the page renders again with its scripts running

### Requirement: A click goes where a click should

The pane SHALL show one document and SHALL NOT navigate away from it. A click
on a link to a remote address SHALL open it in the default browser, as a link
in the markdown preview already does. A click on a link to a file beside it
SHALL open that file, so that the tab bar never names one document while the
pane shows another.

#### Scenario: a link to the web

- **GIVEN** a previewed page linking to a website
- **WHEN** the link is clicked
- **THEN** the browser opens it and the pane still shows the same page

#### Scenario: a link to the next page

- **GIVEN** a previewed `index.html` linking `guide.html` beside it
- **WHEN** the link is clicked
- **THEN** `guide.html` is opened, and the pane showing `index.html` is still
  showing `index.html`

### Requirement: The preview follows the zoom and the theme

The page SHALL grow and shrink with the interface's zoom as every other pane
does. A change of theme SHALL be told to an open pane rather than rebuilding
it, so the scroll position and whatever state the page's own script holds
survive it.

#### Scenario: zooming the window

- **GIVEN** a page previewed at the ordinary zoom
- **WHEN** ⌘+ is pressed until the zoom is 2.0
- **THEN** the page is twice the size, and the source half beside it grew too

#### Scenario: switching theme with a page open

- **GIVEN** a previewed page scrolled half way down
- **WHEN** the theme is changed from light to dark
- **THEN** it is still scrolled half way down
