# Add settings window and auto save (on by default)

`4e0befdd7` · 2026-07-30

Settings (⌘,) is a standard toolbar-style preferences window with Editor,
Saving and Navigator panes. Panes are built from a declarative row list so
adding a setting is one line, and every control is wired to real behaviour —
changes post .ideaiSettingsChanged and open windows apply them live rather than
on next launch.

Settings: editor font size, line height, tab width; auto save with delay and
save-on-focus-loss; show hidden files; excluded folder names; restore defaults.

Auto save defaults to on. This is a browser first, so silently losing edits made
while reading is the worst available outcome. Writes are debounced after the
last keystroke, flushed when the app resigns active and on quit, and closing a
dirty tab writes instead of prompting. A failed automatic save stays silent and
leaves the tab dirty — the user did not ask for that write, so an alert would be
wrong; an explicit ⌘S still surfaces the error.

TextDocument takes an injected Settings rather than reaching for the singleton,
which removed the shared mutable state that made the auto-save tests race under
parallel execution.

Fixes an NSRangeException that would have crashed the app whenever Settings was
opened: NSGridView.column(at:) was called before any rows were added, when the
grid still has no columns.

52 tests.
