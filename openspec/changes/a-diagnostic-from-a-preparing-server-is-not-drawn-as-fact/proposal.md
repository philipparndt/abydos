## Why

Open the Cadova example with nothing built and the first thing on screen is line
1 in red:

    import Cadova        No such module 'Cadova'

The model builds and renders in the pane beside it. Reported from use as *"it
shows an error but works"*, which is the whole of the complaint in five words.

0501 measured this exactly — the server publishes the diagnostic thirteen seconds
after the file opens and withdraws it a minute later, once it has prepared
eighteen targets — and decided **explain, and suppress nothing**: the chip in the
footer says `sourcekit-lsp — preparing`, and its tool tip says that an error here
may be about the build rather than about the code. That was the right call about
*suppression*, and every reason it gives still stands. This change does not
reopen it.

**What it did not settle is how the diagnostic is drawn.** The explanation and
the thing it explains are at opposite ends of the window: the error is red, on
the first line of the file, under the caret, and drawn identically to a mistake
somebody made; the explanation is four words in the bottom-right corner of the
window, in a chip whose ordinary state is the same chip. So the wrong thing is
loud and the true thing is quiet, and the natural response is still to go and
look for a mistake that is not there — which is what 0501 set out to stop and
what was reported again.

There is a second asymmetry worth naming. Preparation is bounded and known: the
server told us it started, and it will tell us when it ends. During that window
the app *knows* the diagnostics are not to be relied on, and draws them at full
confidence anyway. Drawing a thing you know to be provisional as though it were
settled is the part to fix.

## What Changes

- **While a server is preparing, the diagnostics it publishes are drawn as
  provisional rather than as fact.** Same text, same lines, same order, same
  place — drawn in the dimmed weight the editor already has for a hint instead of
  in error red and warning amber, on the underline, in the gutter and wherever
  else a diagnostic appears.
- **Nothing is hidden, nothing is held, and no message is read.** Every
  diagnostic still arrives, still on its line, still with its own words. This is
  a change to weight and colour and to nothing else, which is what keeps 0501's
  three reasons answered rather than argued with.
- **Full strength the moment preparation ends.** Whatever the server publishes
  after that is drawn as it is drawn today; a diagnostic that survives
  preparation was true, and is then said as loudly as any other.
- **Per server, not per window.** A window can have two servers in it, one
  preparing and one that has been answering for an hour. Only the files answered
  by the preparing one are affected — the seam is `LanguageService.isPreparing`,
  which is already keyed by project and language.
- **Not proposed: suppressing by message text.** `No such module` is one
  compiler's wording in one language, and 0501 ruled it out for that reason.
- **Not proposed: holding the batch.** The diagnostics arriving at thirteen
  seconds are not all false — a misplaced brace in the file being edited is real,
  useful, and in the same batch — and holding it throws the true ones away with
  the false ones. This is 0501's reason and it is why this change touches
  drawing and not delivery.
- **Not proposed: a setting.** Worth adding when somebody wants the loud version
  back, and not before.
- **Not proposed: reopening 0461.** A server that will never answer is a
  different sentence in a different place, and it stays where it is.

## Does this contradict the footer requirement?

It sits directly beside one sentence of *The footer says which server is
answering, and from where*, so it is worth answering plainly rather than leaving
a reader to check: **"Nothing is hidden while it says this — the errors stay
exactly where they are."**

Nothing is hidden here either. Every diagnostic is still on screen, on the line
it was published for, saying what the server said. What changes is that it is not
drawn in the colour the editor reserves for *this is wrong*. So the requirement
stands unmodified and this is added beside it — which is also why this change has
no `MODIFIED Requirements` section.

## Capabilities

### New Capabilities

<!-- None. -->

### Modified Capabilities

- `language-servers`: one requirement added. The capability already covers what a
  preparing server's messages are worth — its error-level logs are not counted
  against it, and its empty answers are not evidence — and this is the same
  subject, one step further: what its *diagnostics* are worth while it says it is
  not ready.

## Impact

- `Sources/AbydosApp/Editor/CodeView.swift` — `setDiagnostics` takes whether
  these are provisional, and `color(for:)` answers accordingly. Note that the
  diagnostic colours are two hardcoded hexes here, unlike the find highlights,
  which 0536 moved into the scheme; this change should not leave a third
  hardcoded one behind.
- `Sources/AbydosApp/Editor/EditorViewController.swift` — where diagnostics reach
  the view, and where the file's language and project are already known.
- `Sources/AbydosApp/Editor/LanguageService.swift` — `isPreparing` exists and is
  already keyed by project and language; what is missing is telling the editor
  when the answer changes, since preparation ends without any diagnostic arriving
  to carry the news.
- `Tests/AbydosKitTests/` — the decision of what weight to draw at belongs in
  `AbydosKit`, over a state and a severity, so it is testable without a window.
- No new dependency, and nothing new asked of any server.
