## Context

A scheme file's `app` section has 28 roles and 25 syntax kinds, every one a
light/dark pair. Some roles are text — `editorText`, `gutterText`, the sidebar's
two, the five git colours, the fold placeholder's — and each is drawn on a
ground the same file chooses: the editor's, the sidebar's, the current line's,
the placeholder's. Others are grounds and highlights — selection, find match,
indent guide — and are read as shapes, not letters; `BundledSchemeTests` already
judges those by the relations that matter (the current match outshouts the
others). Syntax kinds are all text on `editorBackground`.

`the-light-terminal-can-be-read` measured the terminal half and left
`SchemeContrast` in the kit with a promised floor per file. Nothing measures the
app half.

## What was measured, 2026-09-09

Every text role against its ground, and every syntax kind against
`editorBackground`, for the four themes in both halves, from the files alone:

| Theme | Half | Roles under 4.5:1 | Syntax under 4.5:1 |
|---|---|---|---|
| blue | light | gutterText 2.47, gitAdded 3.86, gitModified 4.50, gitUnversioned 4.39, gitIgnored 2.93 | comment 3.25 |
| blue | dark | gutterText 2.79, gitIgnored 3.14 | comment 3.90 |
| abydos | light | gutterText 2.42, gitAdded 4.12, gitModified 3.32, gitUnversioned 4.29, gitIgnored 2.81, caret 3.80 | comment 3.72 |
| abydos | dark | gutterText 2.88, gitIgnored 3.41 | comment 3.57 |
| dracula | light | gutterText 2.92, gitConflict 4.44 | — |
| dracula | dark | gutterText 3.03, gitIgnored 3.36 | comment 3.03, documentation 3.03 |
| gray | light | gutterText 2.29, gitAdded 4.38, gitModified 3.47, gitUnversioned 4.49, gitIgnored 2.61 | comment 3.45 |
| gray | dark | gutterText 3.15, gitIgnored 3.24 | comment 3.84 |

So the app half is not the terminal half. Body text and twenty-four of the
twenty-five syntax kinds clear 4.5:1 everywhere. What falls short is, almost
entirely, what is meant to recede: line numbers, ignored files, comments and
documentation — plus, in the light halves, three git colours that are read as
text in the sidebar and the abydos caret.

## Decisions

**Three classes of role, two floors.** Text — `editorText`, `sidebarText`,
`sidebarHeaderText`, `gitAdded`, `gitModified`, `gitUnversioned`,
`gitConflict`, `foldPlaceholderText`, `caret`, and every syntax kind but
`comment` and `documentation` — is held to the promised floor, 4.5:1. Dim text
— `gutterText`, `gitIgnored`, `comment`, `documentation` — is held one step
down, 3:1 under 4.5 and 4.5:1 under 7, the way bright black is in the terminal:
it is meant to be read less, not to be unreadable. Grounds and highlights are
not measured here; they have their own tests.

*Ruled out: one floor for everything.* Line numbers at 4.5:1 stop receding and
the gutter becomes a column of text competing with the code. The reporter's
sentence was about reading, and nobody reads line numbers.

*Ruled out: measuring grounds against grounds.* `currentLineBackground`
against `editorBackground` at 1.1:1 is a feature.

**Every theme clears its floors** the way the palettes did: hue kept, lightness
moved until the pair clears with a margin, the file edited in place. Light-half
git colours darken; dim roles in both halves move a little. The dark tables are
listed in this design because they are the ones in daily use.

*What moved, light halves — 18 values:*

| Theme | Role | Was | Now | Ratio |
|---|---|---|---|---|
| abydos | gitAdded | `#5E7A34` | `#587231` | 4.12 → 4.59 |
| abydos | gitModified | `#B07407` | `#905F06` | 3.32 → 4.64 |
| abydos | gitUnversioned | `#A85A12` | `#A15611` | 4.29 → 4.60 |
| abydos | caret | `#B07407` | `#9E6806` | 3.80 → 4.59 |
| abydos | gutterText | `#B0A28C` | `#9F8E74` | 2.42 → 3.08 |
| abydos | gitIgnored | `#9A8B74` | `#93836B` | 2.81 → 3.11 |
| blue | gitAdded | `#2E8B45` | `#297D3E` | 3.86 → 4.62 |
| blue | gitModified | `#1F6FCC` | `#1E6DC8` | 4.50 → 4.64 |
| blue | gitUnversioned | `#B4553F` | `#AF533D` | 4.39 → 4.58 |
| blue | gutterText | `#A1A5AE` | `#8E939E` | 2.47 → 3.08 |
| blue | gitIgnored | `#8A8F98` | `#868B94` | 2.93 → 3.08 |
| dracula | gitConflict | `#CB3A2A` | `#C73929` | 4.44 → 4.59 |
| dracula | gutterText | `#9A9484` | `#958F7E` | 2.92 → 3.11 |
| gray | gitAdded | `#4E7A38` | `#4B7636` | 4.38 → 4.62 |
| gray | gitModified | `#A87608` | `#8E6407` | 3.47 → 4.58 |
| gray | gitUnversioned | `#A15C18` | `#9E5A18` | 4.49 → 4.64 |
| gray | gutterText | `#ABAAA3` | `#929188` | 2.29 → 3.11 |
| gray | gitIgnored | `#96958D` | `#8A887F` | 2.61 → 3.08 |

*What moved, dark halves — 2 values, said plainly because that is the half in
daily use:*

| Theme | Role | Was | Now | Ratio |
|---|---|---|---|---|
| abydos | gutterText | `#6E5B45` | `#746049` | 2.88 → 3.12 |
| blue | gutterText | `#5C6270` | `#626978` | 2.79 → 3.09 |

Every other value already cleared its floor. Dracula's dark comment and
documentation at 3.03:1 clear the dim floor of 3:1 and stay.

**One theme at 7:1, "WCAG Level AAA".** A whole scheme file: `app` and
`terminal`, `"floor": 7` on both, offered in the Theme list and following the
light-or-dark switch. Its hues are the blue theme's; each text role and syntax
kind is moved until it clears 7:1 against its ground, dim roles 4.5:1. Its
terminal half is the AAA palette that exists, which stays a palette of its own
too so it can be used under another theme.

*Ruled out: making AAA a switch on every theme.* Four themes times two halves
recoloured on the fly is a derivation nobody can look at; a file can be opened
and its numbers checked.

**The measurement is one walk.** `SchemeContrast.shortfalls(in:)` gains the
app half — pairs by class, floor from `app.floor` — and `TerminalContrastTests`
grows a sibling over the same library. `Scheme.read` takes `app.floor` as it
takes `terminal.floor`.

## Risks / Trade-offs

**Syntax colours are chosen for distinctness, and darkening them narrows the
range** → measured after: the pairwise distance between the kinds that moved,
said in the design, and the screenshot read by somebody who codes in the light
theme.

**The AAA theme's light half will look heavy** → it is meant to. The dark half
is pastel, as the palette's is.

## What the pictures showed, 2026-09-09

Six driven screenshots of the same file — a Swift source that is mostly
documentation comments — with the sidebar showing a modified and an untracked
file: the light half of each of the five themes, and the AAA theme's dark half.

- **Blue, abydos, dracula, gray, light**: to a glance, unchanged. What moved
  is line numbers, the ignored grey, the comment green and three git colours,
  each by a shade; the code is the same colours it was. Nothing reads as a
  different theme.
- **WCAG Level AAA, light**: alike at a glance to the blue theme it is derived
  from — the same grounds, the same hues — and different side by side: the
  comment green is deeper, the keyword blue deeper, the untracked file's red
  darker. Twenty-five syntax kinds at 7:1 on white is a page of dark, saturated
  text; the distinctness between kinds is carried by hue and holds.
- **WCAG Level AAA, dark**: pastel and bright, as the palette's dark half is;
  every kind plain against `#1A1C21`.
- **The Theme list**: six entries, WCAG Level AAA last, and the settings
  page reports it as the theme in force under `--theme wcag-level-aaa-light`.

## Release note

> **Themes are measured, and one reaches WCAG Level AAA.** Every theme's text —
> the editor's, the sidebar's, the git colours, every syntax kind — is now
> measured against the ground it is drawn on, in both halves, and held to 4.5:1;
> line numbers, ignored files and comments, which are meant to recede, to 3:1.
> Twenty values moved by a shade to get there, most in the light halves. New in
> the Theme list: **WCAG Level AAA**, the blue theme's hues at 7:1 throughout,
> with the AAA terminal palette as its terminal. A theme of your own can promise
> its floor with `"floor": 7` in its `app` section and be held to it.

## Open Questions

- Whether `caret` is text. It is a shape, but a caret nobody can find is a
  reported bug in every editor; held to 4.5:1 here, said out loud.
