# Add ideai: a fast IDEA-style project browser and editor for macOS

`ae516d79f` · 2026-07-30

Native AppKit project viewer and editor with an IntelliJ-style navigator and
titlebar project switcher, built for reading and lightly editing code without
IDEA's startup time.

Architecture:
- Persistent rope over UTF-8 bytes. Interior nodes sum bytes, UTF-16 units and
  newlines, so byte/UTF-16/line conversions are O(log n). Immutable sharing
  makes a Rope value a free snapshot for the background parser.
- Viewport-scoped syntax highlighting: the tree-sitter query runs only over the
  byte range on screen.
- The parser lives behind a serial queue. tree-sitter reparses incrementally but
  still rebuilds the root's child list (O(siblings), ~25ms on a multi-megabyte
  file), so the rope is authoritative for text on the main thread and the parser
  for colour a frame later. Keystroke cost: 24.9ms -> 0.013ms.

Features: keyboard-navigable tree with context menu, tabs with preview
semantics, tree-sitter highlighting and folding for 19 languages, hex viewer for
binary files, git status colours, FSEvents refresh, JetBrains recents import.

Four grammars are vendored because their manifests gate the external scanner
behind a relative-path fileExists check that SPM never resolves, silently
dropping the scanner and failing to link.

42 tests, including the rope validated against String as a reference model.
