# Say what was being drawn when the drawing killed the app

`6fd9ee99d` · 2026-08-08

The crash that keeps coming back is raised inside CoreText, on a nil value
in a dictionary this app can nowhere be seen to have produced, while
measuring an attributed string. It has now happened twice. Both reports say
plenty about what CoreText was doing and nothing about what was being drawn:
a release build symbolicates by nearest exported symbol, so the two frames
that mattered named a menu action and a port forwarder, neither of which
draws anything.

The app's own handler caught it this time, and that copy is symbolicated —
which is how the site is finally known: a file row under a commit in the
history pane, which fits the report of it happening while resizing the git
panels, since a resize redraws every row.

So those rows leave a note before they draw and the exception handler reads
it: what was being drawn, the font and its size, whether that font can still
be copied — CoreText copies the attributes before typesetting, and a copy
coming back nil is the exact shape of the failure — and the theme and zoom
in force. Two stores of an existing string per row, on a path that draws
tens of rows and not thousands.

The backlog entry is updated with what this narrows: every colour in the
palette is a plain sRGB `NSColor` whose copy is itself, both fonts come from
AppKit and would have trapped at the call if they were nil, and the zoom
steps rule out an absurd size. What is left unchecked is who reads
`Theme.current` — a static var holding thirty-five colours, in a target
built in Swift 5 language mode, where a reader catching an assignment
mid-flight gets a struct belonging to neither palette.
