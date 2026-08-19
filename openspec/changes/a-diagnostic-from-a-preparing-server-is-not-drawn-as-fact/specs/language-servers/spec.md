## ADDED Requirements

### Requirement: A diagnostic from a server that is still preparing is not drawn as fact

While a server is preparing, the diagnostics it publishes SHALL be drawn as
provisional: in a dimmed weight rather than in the colours the editor uses for an
error and a warning, everywhere a diagnostic appears — the underline, the gutter,
and the sentence beside the line.

Nothing SHALL be hidden, held back or read. Every diagnostic SHALL appear, on the
line it was published for, with the server's own words; the message SHALL NOT be
matched against, and the batch SHALL NOT be delayed. `No such module` is one
compiler's wording in one language, and the diagnostics arriving while a server
prepares are not all false — a misplaced brace in the file being edited is real
and arrives in the same batch. So what changes is the weight a diagnostic is drawn
at, and nothing else.

The dimming SHALL follow the server, not the window. A window may hold one server
that is preparing and another that has been answering since it opened; only the
files answered by a preparing server SHALL be drawn this way.

When a server stops preparing, its diagnostics SHALL be drawn at full strength
from that moment, whether or not anything new has arrived. Preparation ends
without a diagnostic to carry the news — the last thing a server sends may be the
withdrawal of the false one, or nothing at all — so the end of preparation SHALL
itself repaint what is on screen.

A diagnostic that survives preparation was true, and there SHALL be nothing left
of this state once the server is ready: the same error, from the same server, on
the same line, SHALL be as loud as any other.

#### Scenario: a package whose dependencies have not been built

- **GIVEN** a Swift package depending on a module that has not been built, opened
  with its build directory empty
- **WHEN** the server publishes `No such module` about the first line
- **THEN** the diagnostic is on that line, saying what the server said
- **AND** it is drawn dimmed rather than in error red
- **AND** the footer chip reads `sourcekit-lsp — preparing`

#### Scenario: a real mistake in the same batch

- **GIVEN** the same package, and a syntax error typed into the file being edited
- **WHEN** both diagnostics arrive together while the server is preparing
- **THEN** both are shown, and neither is held back or dropped

#### Scenario: preparation ends

- **GIVEN** that file, with a diagnostic drawn dimmed
- **WHEN** the server finishes preparing and withdraws the false one
- **THEN** it goes, as it does today

#### Scenario: preparation ends and the diagnostic was true

- **GIVEN** a file whose diagnostic is a genuine mistake, drawn dimmed while the
  server prepared
- **WHEN** the server finishes preparing and publishes it again
- **THEN** it is drawn in error red, without waiting for anything else to happen

#### Scenario: two servers, one of them ready

- **GIVEN** a window with a Swift file whose server is preparing and a Go file
  whose server has been answering since the project opened
- **WHEN** both publish diagnostics
- **THEN** the Swift file's are dimmed and the Go file's are not

#### Scenario: a server that was never preparing

- **GIVEN** a project opened a second time, with everything already built
- **WHEN** a file is opened and its server answers without a preparation stretch
- **THEN** its diagnostics are drawn in the ordinary colours from the first frame
