# Choose source, preview or split from the tab bar

`a110bccf0` · 2026-07-31

Markdown had a preview toggle and models had a viewer, each with its own
rules. They are one idea: a file that has both a source and a rendered
form, and a choice of which to look at. A control at the trailing edge of
the tab strip offers Source, Preview and Split, and follows the active
tab.

Split puts the source on the left — reading order, and the thing being
edited stays where it was.

What a file offers is decided in one place rather than by each feature
testing extensions of its own. A mesh has no source worth reading, so an
STL opens rendered and is offered only Preview; a .scad or a .md is
written by hand, so it opens as itself and the preview is asked for.

The viewer is hosted on the editor's background. A SwiftUI view leaves
its unpainted regions transparent, which showed through as a different
shade from the code beside it.
