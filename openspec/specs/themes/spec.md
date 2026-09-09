# themes Specification

## Purpose
TBD - created by archiving change a-theme-at-wcag-level-aaa. Update Purpose after archive.
## Requirements
### Requirement: A theme's text can be read on the ground it is drawn on

Every bundled theme SHALL have, for each role that is read as text and for each
syntax kind, a contrast ratio against the ground it is drawn on that meets the
floor its file promises — 4.5:1 unless the file says more — in both its light
and its dark half. Roles that are meant to recede — line numbers, ignored files,
comments and documentation — SHALL be held one step below that floor. Grounds
and highlights are not text and are judged by their own relations. A test SHALL
measure every bundled theme on every run and name the role, the half, the
ground and the ratio of anything short.

#### Scenario: A comment in the light theme

- **GIVEN** any bundled theme in its light half
- **WHEN** a comment is drawn on the editor's ground
- **THEN** it reads at 3:1 or better, and the code around it at 4.5:1 or better

#### Scenario: A changed file in the sidebar

- **GIVEN** any bundled theme, either half
- **WHEN** the sidebar colours a file as added, modified or unversioned
- **THEN** the name reads at 4.5:1 or better against the sidebar's ground

### Requirement: One shipped theme reaches Level AAA in both halves

The app SHALL ship a theme, "WCAG Level AAA", whose file promises 7:1 for its
app half and its terminal half, and whose text roles and syntax kinds reach 7:1
against their grounds — dim roles 4.5:1 — in light and in dark. It SHALL appear
in the Theme list and follow the light-or-dark setting like every other theme.

#### Scenario: Choosing the theme

- **GIVEN** the Theme list in Settings
- **WHEN** WCAG Level AAA is chosen, in either half
- **THEN** every text role and syntax kind reads at 7:1 or better on its ground,
  and the terminal follows with the AAA palette

