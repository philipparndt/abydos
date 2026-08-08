# A dialog with something to say lays it out wide enough to read

`1a4d444b3` · 2026-08-05

The install instructions for a language server came up blank. So did anything
else that dialog was ever asked to show — it is the same panel behind every
toast's "Details", so helm's output, the compiler's, kubectl's, all of it.

The text view was a plain `NSTextView()`, which has a frame of zero, handed to
a scroll view as its document view. A scroll view does not size its document
view unless the view says it tracks the width, so the frame stayed at zero and
so did the text container. A container that narrow cannot fit a single
character, so every glyph was pushed onto a line of its own and off the left
edge — which is why the scroller showed a great deal of content beside an empty
panel. That scroller is the tell, and it is the one part of the picture that
was telling the truth.

The four lines that fix it are the ones the markdown preview already had
(`EditorViewController.swift:1396`); this dialog was written without them.

`--detail-dialog` opens the thing over the window so the capture harness can
see it, since it is otherwise three clicks and a machine with no typescript
server installed. `LanguageServers.Suggestion` gains the public initialiser
that hook needs to build a real one.
