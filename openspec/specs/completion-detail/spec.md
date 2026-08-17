# completion-detail Specification

## Purpose
TBD - created by archiving change completions-say-what-goes-in-them. Update Purpose after archive.
## Requirements
### Requirement: The selected completion's documentation is on screen

Where a server sends `documentation` with a completion item, the editor SHALL show
it for the item the list has selected, beside the list, and SHALL follow the
selection as it moves. The documentation is what answers "what goes in here":
openscad-lsp sends 1530 characters for `cube`, of which the sentence that matters
is *"size — single value, cube with all sides this length; 3 value array [x,y,z]"*,
and it is parsed today and dropped between `LSPCompletion` and `CompletionItem`.

Where a server sends none, nothing is drawn — an empty panel beside the list is a
worse answer than no panel, because it reads as "there is nothing to know".

#### Scenario: taking the `cube` completion in a `.scad`

- **GIVEN** a running `openscad-lsp` and `cub` typed in a `.scad`
- **WHEN** the list appears with `cube(size, center=false)` selected
- **THEN** the server's prose for `cube` is shown beside the list
- **AND** it names `size` as either a single value or a three-value `[x, y, z]`

#### Scenario: the documentation follows the selection

- **GIVEN** that list, showing `cube`'s documentation
- **WHEN** ↓ moves the selection to `cylinder(h, r, center=false)`
- **THEN** the panel shows `cylinder`'s documentation instead

#### Scenario: an item with nothing said about it

- **GIVEN** a completion that came from the words already in the file, or a server
  item with no `documentation`
- **WHEN** it is selected
- **THEN** no documentation panel is drawn at all

#### Scenario: the list never moves to make room

- **GIVEN** the caret near the right-hand edge of the screen
- **WHEN** the list and its documentation are shown
- **THEN** the list is where it would have been without the panel
- **AND** the panel takes whichever side has room, or is not shown if neither has

### Requirement: A server's markdown is reduced before it is drawn

The editor SHALL reduce a server's documentation to readable text before drawing
it, and SHALL NOT draw markup as text or fetch anything named in it.
Documentation arrives as markdown from both servers driven so far, and
openscad-lsp's contains fenced code blocks, `**bold**` runs, HTML `<table>`
markup and `<img>` tags pointing at remote images. `LSPHover.text(from:)`
unwraps the `MarkupContent` envelope only and is not sufficient on its own.

The reduction SHALL live in `AbydosKit` and be testable without a window.

#### Scenario: markup does not reach the screen

- **GIVEN** `cube`'s documentation from openscad-lsp
- **WHEN** it is reduced for the panel
- **THEN** no ```` ``` ```` fence, no `**` pair and no `<` tag is in the result
- **AND** the parameter description for `size` still is

#### Scenario: a remote image is not fetched

- **GIVEN** documentation containing `<img src=https://upload.wikimedia.org/…>`
- **WHEN** it is shown
- **THEN** nothing is requested over the network
- **AND** the surrounding prose is still shown

#### Scenario: the panel is bounded

- **GIVEN** documentation longer than the panel can hold
- **WHEN** it is shown
- **THEN** the panel keeps its bounded height and the rest is reachable by
  scrolling, rather than the panel growing to the height of a wiki page

