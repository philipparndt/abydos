# Watch what is selected, from where you are looking at it

`f7fe65733` · 2026-08-06

Selecting an expression and asking to watch it is the short way round. The
long way is reading it, remembering it, finding the watch field and typing it
back in, during which the thing being debugged has not moved but the
attention has.

Offered only with a selection, because the selection is what would be
watched: `things[i].name` is an expression, and no rule about the identifier
under the caret would have picked it out. The pane switches to the variables
with it — a watch added by somebody looking at the editor, answered on a tab
they are not looking at, is a question that appears to have done nothing.

Verified through the debug harness: added=true, and the console tab gave way.
