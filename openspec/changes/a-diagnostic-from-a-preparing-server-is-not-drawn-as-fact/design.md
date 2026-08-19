## Context

Three things exist already, and this change is mostly deciding what to do with
the one that is not yet asked.

**The state.** `LanguageService` keeps `preparing: Set<String>`, keyed by project
and language, and already answers `isPreparing(project:languageId:)` — added by
0501 so the footer chip could say the word. It is filled from work-done progress,
which is the protocol's own rather than any one server's wording, and only the
first stretch of it counts.

**The delivery.** `LSPClient.onDiagnostics` arrives, `EditorViewController` routes
it to the tab for that file, and `CodeView.setDiagnostics` groups it by line and
sets `needsDisplay`. Nothing between the wire and the view looks at the message
text, and this change must not be the thing that starts.

**The drawing.** `CodeView.color(for:)` is a `switch` over severity returning two
hardcoded hexes — `0xE05252` for an error, `0xD9A343` for a warning — and
`.hint`/`.information` already fall through to `Theme.current.gitIgnored`, which
is the dimmed weight this change wants. So the quiet colour is already in the
file and already used; what is missing is a reason to reach it.

## Decisions

**Weight, not visibility.** The alternatives were suppression and delay, and
0501 measured both out: suppression cannot tell a dependency that is genuinely
missing from one that is not built yet, and delay throws the true diagnostics in
the batch away with the false ones. Weight is the axis neither of them is on. The
diagnostic is present, complete and in place — it is only not asserted, which is
exactly the app's state of knowledge while the server has told it that it is not
ready.

**Through the scheme, not a third hex.** `color(for:)` should not gain a
hardcoded dim colour beside the two it has. 0536 moved the find highlights out of
this view and into the scheme files, for the reason that a colour chosen against
one dark ground is wrong on every light one, and diagnostics are the same shape
of thing. Either the two severities move with it or the provisional weight is
derived from what is already there; deciding which is part of the work rather
than of this document, but a third literal is the answer to rule out.

**Decided in the work: derived, and no scheme keys added.** The quiet weight is
`Theme.current.gitIgnored` — the colour `hint` and `information` have always
been drawn in — so a scheme that has been thought about is thought about here
too, and this change adds no colour at all. `color(for:)` now takes a
`DiagnosticWeight` rather than a severity, which is what makes the third literal
impossible rather than merely absent. Moving the two severities into the scheme
files remains worth doing and is a change of its own: it would touch every
shipped scheme and `SchemeTests`, and none of that is needed to stop a false
error shouting.

**Repaint on the end of preparation, not on the next diagnostic.** This is the
part that is easy to get wrong and is invisible when it is. Preparation ends when
the server closes its progress token, and the last diagnostic may have arrived
thirty seconds earlier — so a view that only redraws when something new arrives
would keep a dimmed error on screen after the server was ready, which is worse
than the state this change is fixing. `LanguageService` already removes the key;
it has to say so as well.

**Keyed by server, and the key already exists.** `isPreparing` takes a project
and a language, which is what a tab knows about its own file. Nothing new has to
be threaded through, and a window holding a preparing Swift server and a settled
Go one behaves correctly by construction rather than by a special case.

**The decision itself in `AbydosKit`.** What weight a diagnostic is drawn at is a
function of a severity and whether the server is preparing, and that is a claim
worth a test — `anErrorFromAPreparingServerIsDrawnAsAHintIs`, and its twin for
the ready case. `CodeView` is then placement, as it is for the inline values and
the find bands.

## Risks

**The quiet version is quiet.** The point is to stop a false error shouting, and
the cost is that a *true* error is also quiet for its first minute on a cold
project. That is accepted, and it is bounded: it lasts as long as preparation,
the footer names the state throughout, and the diagnostic is still on the line
with its own words. A reader who looks at it learns the same thing; what they no
longer do is look at it because it was red.

**A server that reports progress forever.** If a server never closes its first
progress stretch, everything it says stays dim. That failure already exists —
the chip would say `preparing` forever too — and 0501's rule that only the first
stretch counts is what bounds it. Worth a look at whether the chip and this
should share a ceiling; not worth inventing one here.
