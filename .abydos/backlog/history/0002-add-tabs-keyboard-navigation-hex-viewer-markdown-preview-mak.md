# Add tabs, keyboard navigation, hex viewer, markdown preview, Makefile

`ad0a26457` · 2026-07-30

Editor:
- Tabbed file area with preview semantics: a single click in the tree opens a
  provisional tab (italic) that the next click replaces; double-click, Return or
  editing pins it. Each tab owns its view, so caret, scroll and folds survive
  switching.
- Binary and oversized files open as an in-editor notice with "open externally"
  and "open in hex editor" instead of a blocking alert. The hex viewer maps the
  file and draws only visible rows.
- Markdown preview (⇧⌘V) rendered natively from Foundation's CommonMark parser,
  with GFM pipe tables rendered as aligned monospace since Foundation does not
  parse them.

Navigator:
- Full keyboard navigation with IDEA semantics: arrows move and expand, Return
  opens and focuses the editor, Space previews, typing jumps to a name.
- Context menu: open, open externally, reveal in Finder, copy path, rename,
  move to trash.
- Rounded selection highlight.

Fixes:
- Directories containing ignored files were themselves rendered as ignored,
  greying out most of a normal project. Ignored children no longer roll up.
- selectionHighlightStyle .none suppressed drawSelection entirely, so the
  custom highlight never drew.
- Expanding a folder by keyboard lost the selection: the git-status refresh
  called reloadData, which clears it. Status changes now repaint in place.
- SF Symbols drawn via NSImage.draw were rendering black in dark mode;
  NSColor.set() does not tint a template image, so colour is now baked into the
  symbol configuration.
- Titlebar insets are measured from the window rather than hardcoded, which was
  clipping the tab bar.

Also adds OpenSCAD support (19 languages) and a Makefile.
