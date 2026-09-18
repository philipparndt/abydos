# A song is edited in one tab

## The question with no answer

A song pane used to work out which song its file belonged to. It asked the
language server — `mat/timeline` carries a `song` — held its first render for a
moment and a half waiting for the answer, and then re-pointed itself at whatever
came back: let go of the playback, cancelled the render, changed its song and
started again.

Two things were wrong with it, and the second is the fatal one.

- **It stopped the sound.** Every navigation into an included file was a pane
  tearing down a render and starting another, so a song being worked on stopped
  and restarted for every file its author opened. Reported 2026-09-16: "jumping
  to other files and keep the stream does not really work … It stops very often".
- **A file cannot answer it.** "Lets say we have a library with snippets, who
  should it know." A file of patterns can be included by five songs or by none.
  The server answers with *a* song because it has one file open; another session
  with another song open would answer differently, and both would be right.

The song is the thing that knows. It is the file that includes the others, and
the render's manifest and the server's timeline both list what it is made of.

## The shape

**A tab's `url` is the file it is showing; a tab's `song` is what the tab is.**
That way round on purpose: about a hundred and thirty places read `tab.url`, and
all but a handful of them mean "the file in front" — find, save, the caret, the
status bar, the server's `didOpen`, the breakpoints, the tab's name. Those keep
working untouched. The few that mean "which song is this tab" — the pane, the
playback, the debug session — ask `song`.

A song's tab keeps **one source half per file**: the document, the code view,
the scroll view, the server root and the find state. Switching puts the half in
front away whole and brings the other back, so a file comes back the way it was
left: same caret, same folds, same scroll, same undo. Nothing is re-read and
nothing is re-parsed.

**The pane is not told anything.** The song has not changed, so there is nothing
for it to do — it keeps its render, its playback and its playhead. The only
thing that moves is which code view its caret lighting, timeline bars and loop
clicks are tied to.

## What it cost

`makeTab` built a document, a code view, twenty-odd callbacks and the server's
`didOpen` in one three-hundred-line run, all bound to one file. That comes apart
into `makeCodeSource()` and `wire(_:of:document:in:)` — the file and the tab
showing it, given separately — which is what lets a tab build a second one. Four
callbacks were reaching for `tab.url` where they meant the file; they now take
the file they were made for, which is the same thing for every ordinary tab.

The swap looks at **where the outgoing view is**, not at what the tab is. The
first attempt looked for the split at the top of the tab, found the crumb row's
stack around it, and swapped nothing: reported at once as "the file change does
not change the editors content".

## What it looks like

`♪ drive.song ⌄ › parts › bass.song`. The song's name opens a menu of every file
the song is made of, ticked where you are; the trail says where that is. A tab
that is not a song's has no such row.

The chevron is a symbol beside the name rather than a `⌄` in the title: a glyph
in the text sits on the baseline, under the middle of the name — "the chevon
shall be centered", with a picture.

## Driven

On the drive example, rendered once, at load 25:

| Step | Tabs | The pane | Playhead |
| --- | --- | --- | --- |
| the song | `[quick.song]` | playing, `runs=1` | 8.35 s |
| `drums.song` | `[drums.song]` | the same pane, playing | 11.57 s |
| `parts/bass.song` | `[bass.song]` | seven stems landed | 14.67 s |
| back to the song | `[quick.song]` | never stopped | 18.02 s |

One tab throughout, one render, and a playhead that only goes forward.

## The jumps themselves

The language server had go-to-definition all along — `definitionProvider`, and
asked directly it answers for an include's name, an instrument's and a pattern's,
across files. It answered *nothing* for the keyword beside them, and the editor
did nothing with that nothing, which is indistinguishable from a server that
cannot jump at all: "it seems not be possible to navigate to includes and
functions - do we miss a navigation feature in the LSP?"

Both halves are fixed. `mat` d5e0958 takes the keyword as the name beside it, so
`include`, `play` and `instrument` all go where their names go — measured
against the real server, all three now answer — and a jump that finds nothing
says so instead of doing nothing.
