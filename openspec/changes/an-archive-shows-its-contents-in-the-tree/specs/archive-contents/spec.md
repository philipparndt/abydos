## ADDED Requirements

### Requirement: An archive row offers to show its contents

The project tree SHALL offer *Show Contents* on the context menu of a file
that is a zip or a zip under another name, a tar, a gzipped tar, or a lone
gzip, and SHALL NOT offer it on any other row. Chosen, the row SHALL become
expandable and open like a folder, with the archive's directories as folder
rows and its entries as file rows, each entry with its size in the grey half,
and nothing SHALL be written inside the project to show it. The item SHALL
then read *Hide Contents*, which makes the row a leaf again. The kind SHALL
be decided from the first bytes, so a misnamed file says it is not an archive
rather than showing nothing.

A downloaded Helm chart is a `.tgz`, and what somebody wants from it is one
look at `values.yaml`; unpacking it beside itself to get that look leaves a
directory git wants to know about.

#### Scenario: a chart

- **GIVEN** `multi-tier-0.1.0.tgz` in the tree
- **WHEN** *Show Contents* is chosen on it
- **THEN** the row opens on `multi-tier/` holding `Chart.yaml`,
  `values.yaml` and `templates/`, and no directory appears on disk

#### Scenario: a text file

- **GIVEN** `README.md` selected
- **THEN** its context menu has no *Show Contents*

#### Scenario: hiding again

- **GIVEN** an archive shown
- **WHEN** *Hide Contents* is chosen
- **THEN** the row is a leaf and the item reads *Show Contents*

#### Scenario: a jar

- **GIVEN** a `.jar`
- **WHEN** *Show Contents* is chosen
- **THEN** it opens on `META-INF/` and the packages inside it

### Requirement: The archive is listed, not unpacked

Showing an archive SHALL read what it costs to list: a zip from its central
directory, a tar by its headers, a gzipped tar by inflating it in memory up
to a cap and saying so past it, a lone gzip as one entry. The listing SHALL
be made off the main thread with the row saying it is reading meanwhile, and
SHALL be kept keyed on the archive's size and modification time, so a file
replaced under an open row is read again on the next expand.

#### Scenario: a large jar

- **GIVEN** a 200 MB jar with ten thousand classes
- **WHEN** it is shown
- **THEN** its rows appear from the central directory alone, without the
  members being read

#### Scenario: a chart pulled again

- **GIVEN** a chart shown, then replaced on disk by a newer version
- **WHEN** its row is collapsed and expanded
- **THEN** the new version's entries are listed

#### Scenario: past the cap

- **GIVEN** a `.tgz` that inflates past the cap
- **WHEN** it is shown
- **THEN** the row says the archive is too large to show inline and offers
  nothing else

### Requirement: An entry opens read only, and says where it is

An entry chosen in the tree SHALL open in the editor as a read-only tab
whose subtitle names the archive, with syntax, find, the structure pane and
*Open as Hex* working as on any file. Typing into it SHALL be declined, and
⌘S SHALL say the file is inside the archive and name *Extract…* as the way
to a file that can be changed. The bytes SHALL come from the archive — a
stored or deflated zip member, a tar member — through a copy under the
system's cache directory keyed to the archive, never inside the project.

A buffer that can be typed into and never saved is the worse design: the
person finds out at ⌘S that ten minutes went into a copy.

#### Scenario: reading the default values

- **GIVEN** the chart shown
- **WHEN** `values.yaml` is chosen
- **THEN** it opens with YAML highlighting, the tab says *inside
  multi-tier-0.1.0.tgz*, and a keystroke into it changes nothing

#### Scenario: ⌘S on an entry

- **GIVEN** `values.yaml` from the chart in front
- **WHEN** ⌘S is pressed
- **THEN** nothing is written and the message names the archive and
  *Extract…*

#### Scenario: a member the platform cannot inflate

- **GIVEN** a zip member compressed with bzip2
- **WHEN** it is chosen
- **THEN** the tab is a notice saying the method is not one this app can
  read, and the row is still listed

### Requirement: One entry can be extracted beside the archive

An entry row's context menu SHALL offer *Extract…*, which writes that entry
— a directory with its subtree — beside the archive under its own name, asks
before overwriting anything, and selects what it wrote. Whole-archive
extraction SHALL NOT be offered.

#### Scenario: keeping the values

- **GIVEN** `values.yaml` inside the shown chart
- **WHEN** *Extract…* is chosen
- **THEN** `values.yaml` exists beside the `.tgz`, is selected in the tree,
  and opens as an ordinary file

#### Scenario: a name already taken

- **GIVEN** a `values.yaml` already beside the archive
- **WHEN** *Extract…* is chosen on the entry
- **THEN** it asks before writing over it

### Requirement: The shown archives come back with the tree

Which archives are shown SHALL be kept with the tree's folds in the project's
session, as `archive:<path>` keys beside the folder keys, and restored with
them, so a chart opened before a project switch is open after it and an
archive nobody asked about is a leaf.

#### Scenario: across a switch

- **GIVEN** a chart shown and its `templates/` open
- **WHEN** the project is left and opened again
- **THEN** the chart is shown with `templates/` open, and the other archives
  in the tree are leaves

### Requirement: The example project carries a packaged chart

`abydos-examples` SHALL carry `multi-tier/deploy/charts/multi-tier-0.1.0.tgz`,
packaged from the chart beside it, with the Makefile's `charts` goal making
it and the README saying what it is for.

#### Scenario: opening the example

- **GIVEN** `abydos-examples/multi-tier` open as a project
- **WHEN** *Show Contents* is chosen on the packaged chart and `values.yaml`
  chosen inside it
- **THEN** the defaults are on screen and nothing was unpacked

### Requirement: The archive rows are driven from the launch options

The `--tree` steps SHALL gain `show-contents` and `hide-contents` on the
selected row and `extract` on a selected entry, and the `menu` step's report
SHALL include the archive items, so the proof is a report and a screenshot.

#### Scenario: a driven show

- **GIVEN** `--tree "…,show-contents,right,down,selected"` on a chart row
- **THEN** the report lists the chart's first entry selected
