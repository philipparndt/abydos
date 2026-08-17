# completion-triggers Specification

## Purpose
TBD - created by archiving change completions-say-what-goes-in-them. Update Purpose after archive.
## Requirements
### Requirement: The list is offered where a server says it should be

The editor SHALL ask for a completion list on the second character of a word, and
on any character a server named in `completionProvider.triggerCharacters`.
sourcekit-lsp names `.` and `(`; the two-character rule alone means the editor
never asks after a `.`, so an enum case can never be offered — `WordMotion.prefix`
stops at the dot and returns nothing, and `scheduleCompletions` gives up before
the request.

A server that names no trigger characters — openscad-lsp names none — SHALL behave
exactly as it does today. Trigger characters SHALL come from the capabilities the
client stored at `initialize`, not from a list of characters kept in the editor.

#### Scenario: a dot where an enum case belongs

- **GIVEN** a warm `sourcekit-lsp` and `.offset(amount: mouth, style: ` typed
- **WHEN** `.` is typed
- **THEN** the list is asked for straight away, without a second character
- **AND** it offers `round`, `miter`, `bevel` and `square`

#### Scenario: a server with no trigger characters

- **GIVEN** `openscad-lsp`, whose `completionProvider` is empty
- **WHEN** `.` is typed in a `.scad`
- **THEN** no request is sent, exactly as before

#### Scenario: the debounce still applies

- **GIVEN** a trigger character typed
- **WHEN** more characters follow it immediately
- **THEN** one request is sent for where the typing stopped, not one per keystroke

### Requirement: Items are matched the way the server asked for

Where a completion item carries `filterText`, the editor SHALL match against that
rather than against `label`. Both servers send labels that are whole signatures —
`cube(size, center=false)` with `filterText: "cube"`, and
`withUnsafeCurrentTask(body: (UnsafeCurrentTask?) throws -> T) rethrows` with
`filterText: "withUnsafeCurrentTask(body:)"` — so matching on the label keeps the
items whose signature happens to start with the typed word and throws away the
rest.

#### Scenario: a label that is a signature

- **GIVEN** an item labelled `cube(size, center=false)` with `filterText` `cube`
- **WHEN** `cub` has been typed
- **THEN** the item is offered

#### Scenario: a label whose start is not the name

- **GIVEN** a sourcekit-lsp item whose label begins with its argument list or a
  qualifier and whose `filterText` is the name
- **WHEN** the name's first characters are typed
- **THEN** the item is offered, where today it is filtered out

#### Scenario: an item with no filterText

- **GIVEN** an item that sends none
- **WHEN** matching happens
- **THEN** the label is used, as now

### Requirement: A server that is not ready says so instead of being replaced

An empty answer from a server that is still preparing SHALL NOT be replaced by the
words already in the file. Measured against `sourcekit-lsp` and a Cadova package,
the first useful answer came 123 seconds after the file was opened; at 1, 11, 32
and 62 seconds it answered nothing, with no error, while it built 651 files. What
the editor shows in that window today is the file's own words, which looks like an
answer and is not.

While `LanguageService` holds the server in `preparing`, the list SHALL say the
server is still preparing, and SHALL be asked again when the existing
`onPreparing(false)` callback fires — not on a poll and not on a timer.

#### Scenario: completing in a cold package

- **GIVEN** a Swift package whose server is preparing
- **WHEN** the list would be shown
- **THEN** it says the server is still preparing
- **AND** it does not show the words already in the file as if they were the answer

#### Scenario: the answer arrives

- **GIVEN** that list saying the server is preparing, and the caret still in the
  same word
- **WHEN** the server finishes preparing
- **THEN** the list is asked again and shows what the server says

#### Scenario: a language with no server at all

- **GIVEN** a file no server answers for
- **WHEN** a word is typed
- **THEN** the words already in the file are offered, exactly as today

