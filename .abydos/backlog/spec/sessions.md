# Sessions

What a project remembers between one sitting and the next: which files were
open, how each was being shown, where the terminals were, what the play button
was pointing at. It is kept beside the project, so it belongs to the project
rather than to the application — switching to another project and coming back,
and closing the window and opening it again, are the same thing to it.

Only the tabs are described here so far. The terminals, the breakpoints, the
chosen configuration and the subproject are remembered too and none of them has
been written down yet; whoever touches one of them has a file to add to.

## Requirement: A tab comes back in the mode it was being shown in

A file with both a source and a rendered form is shown in one of four modes —
the source, the rendered form, or one of the two splits — and which one is a
property of the tab. It is written into the session beside the path and the
line, so a tab put in Split Right is still in Split Right when the project it
belongs to is opened again. Switching project rebuilds the whole tab set, and a
relaunch builds it from the file on disk; both put back what was there.

### Scenario: a model beside its source, across a project switch

- **Given** a `.scad` open in Split Right, with the model beside the source
- **When** another project is opened in the window and then that one again
- **Then** the tab is in Split Right, with the model still beside the source

### Scenario: a document and its rendering, one above the other

- **Given** a `.md` open in Split Down
- **When** the project is opened again
- **Then** the tab is in Split Down

## Requirement: A split comes back with its divider where it was left

The divider is remembered with the mode, as a fraction of the pane rather than a
position — the pane is not the size it was in another window, on another screen,
or beside a sidebar somebody has since dragged. A split restored to an equal
half is not the tab somebody left, so the fraction travels with the mode.

A tab that is not the one in front has no geometry at all until it is clicked,
so the fraction is held until the split has been laid out with room for both
halves, and applied then.

### Scenario: a divider three quarters of the way across

- **Given** a `.scad` in Split Right with the source taking three quarters of
  the pane
- **When** another project is opened and then that one again
- **Then** the source still takes three quarters of the pane

### Scenario: a split behind the tab in front

- **Given** two files restored together, the split one behind the other
- **When** its tab is clicked for the first time
- **Then** its divider is where it was left, not at the half it never had

## Requirement: A session that says nothing about a mode gets the file kind's default

A session written before modes were recorded, or by anything that does not write
them, has no opinion about how a file was being shown — and no opinion means the
default for that kind of file, not the source. A picture opens as the picture, a
PlantUML or Mermaid file opens as both halves, and a Markdown file opens as text,
exactly as each does when it is opened for the first time.

### Scenario: a session from before the mode was recorded

- **Given** a session file listing a `.mmd` and a `.scad` with no mode against
  either
- **When** the project is opened
- **Then** the `.mmd` is in Split Right and the `.scad` is its source

## Requirement: A mode is ignored for a file that cannot be shown in it

A mode is only meaningful where there is something to show. A session may name
one against a file that has no rendered form, or one that has no source half to
put beside it — a file renamed, or a session written by hand — and the file kind
decides instead of the note.

### Scenario: a split written against a file with no preview

- **Given** a session naming Split Right against a `.swift`
- **When** the project is opened
- **Then** the tab is its source, and no split is made

### Scenario: a split written against a document with no source half

- **Given** a session naming Split Right against a `.drawio`, whose own editor
  owns the document
- **When** the project is opened
- **Then** the tab is the draw.io editor, filling the pane
