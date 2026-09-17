# Markdown Preview

## Purpose

How a rendered markdown document is set in the pane beside or instead of its
source: its blocks, its type, its code, and that it follows the zoom.

## ADDED Requirements

### Requirement: A fenced code block is one block

A fenced code block SHALL be laid out as a single block: one background surface
a step off the editor's background, padding on all four sides, and the code's
own line spacing inside it with no paragraph spacing between its lines. Its
text SHALL remain selectable, and copying the block SHALL yield the code and
nothing else. A fence with no language, or one no grammar answers for, SHALL be
set in the editor's text colour on that surface; a fence with a grammar SHALL be
coloured by it. No git status colour SHALL be used anywhere in the preview.

Reported 2026-09-17 with a screenshot: seven lines of shell in a fence rendered
with a blank line's worth of air between each, in the green a file is when it
is new to git, with nothing to say where the code began.

#### Scenario: a shell fence with no language

- **GIVEN** a fence of seven lines with no language after its backticks
- **WHEN** the preview is shown
- **THEN** the seven lines sit on one panel with equal, code-height line
  spacing, in the body text colour, with room between the panel's edge and the
  first and last line and the left edge of the text

#### Scenario: copying the block

- **GIVEN** that panel
- **WHEN** its text is selected and copied
- **THEN** the pasteboard holds the seven lines and no padding characters

#### Scenario: the commit-message pane

- **GIVEN** a commit whose message holds a fence
- **WHEN** it is shown in git history
- **THEN** the fence is on the same panel

### Requirement: Headings are set like a page's

Heading sizes SHALL be in proportion to the body — 2, 1.5, 1.25, 1, 0.875 and
0.85 times it — with a rule under levels one and two in the separator colour,
more space above a heading than below it, and level six in the dimmer heading
colour. A thematic break SHALL be a drawn line, not a string of dashes.

#### Scenario: a README's title

- **GIVEN** a document beginning `# @vehub/screencast-kit` and a paragraph
- **WHEN** the preview is shown
- **THEN** the title is twice the body size with a one-point rule under it,
  and the paragraph starts a body height below the rule

#### Scenario: a horizontal rule

- **GIVEN** `---` on a line of its own between two paragraphs
- **WHEN** the preview is shown
- **THEN** a line in the separator colour spans the text column, and no dash
  characters are in the rendered text

### Requirement: The type is set to read

The body SHALL be set at a line height of 1.5 with a body height between
paragraphs. Inline code SHALL be set at 85 % of the body on a rounded pill with
room around the letters, adding no characters to the text. A list marker SHALL
hang in the margin so wrapped lines align with the item's first word. A block
quote SHALL carry a bar down its left edge and its text in a dimmer colour.
Links SHALL be in the scheme's link colour.

#### Scenario: a paragraph with inline code

- **GIVEN** `A repo owns one \`screencast.yaml\`; everything else is the kit.`
- **WHEN** the preview is shown
- **THEN** `screencast.yaml` is on a rounded pill wider and taller than its
  glyphs, and selecting the sentence and copying it yields the sentence with
  no extra spaces

#### Scenario: a wrapped list item

- **GIVEN** a bulleted item long enough to wrap in the pane
- **WHEN** the preview is shown
- **THEN** the second line begins under the first word, not under the bullet

### Requirement: The preview follows the zoom

Every size in the preview SHALL derive from one body size taken from the
theme's scale, so the preview grows and shrinks with the interface's zoom as
every control does, and the text container's inset SHALL scale with it.

#### Scenario: zooming the window

- **GIVEN** a preview at the ordinary zoom
- **WHEN** ⌘+ is pressed until the zoom is 2.0
- **THEN** the body, the headings, the code and the panel's padding are twice
  what they were, within rounding, and the source half beside it grew too
