# The status bar belongs to the editor, not to the panel

`9778b4bbe` · 2026-08-06

It was drawn in the sidebar's shade with a hairline along its top, and the
panel's tab strip directly below it is drawn in the sidebar's shade with a
hairline along its top. Two identical bands touching read as one, which is how
a double-click meant for the status bar landed on the tab strip and maximised
the panel.

The editor's background instead, which is also what this bar is: it says where
the caret is and what the file is. The lighter band is now the panel's alone,
and the two are told apart by the thing they differ in.
