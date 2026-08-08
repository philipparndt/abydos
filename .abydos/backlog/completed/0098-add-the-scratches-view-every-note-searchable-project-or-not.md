# Add the Scratches view: every note, searchable, project or not

`ce405fde5` · 2026-08-01

A scratch was only as findable as the tab it was in. Close the tab and the
note was still on disk, but nothing in the window could reach it — which is
no way to treat the only copy of something.

The fifth sidebar tool (⌘5) lists them all: the project you are in first,
then the ones that belong to no project, then every other project's. The
search field reads what is written inside them, not just their names —
a scratch is usually unnamed, so its name is the one thing you cannot look
for it by. Hits show the line they were found on.

New Global makes a note that belongs to no checkout, for the things that
outlive one: a language, a machine, a way of doing something. A note can be
renamed, moved between a project and global, revealed in Finder, or deleted
— deleting always asks, since this is now the one place a note can be lost
from. Anything renamed or moved is followed by the tab showing it, and
unsaved text is written out first so the rename carries it.

Restoring changes with it. Reopening every scratch a project has ever had
was fine with three and absurd with thirty, so which ones were open is
recorded as tabs change — surviving a crash as well as a quit — and only
those come back. The rest are one search away rather than in a tab nobody
asked for. Projects reached by two spellings of the same path (/tmp and
/private/tmp) now resolve to one pile of notes rather than two.

Closing an empty scratch still throws it away, but only when it is empty
both on disk and in the editor: a document holding text the file does not
is exactly the case where deleting would lose something.
