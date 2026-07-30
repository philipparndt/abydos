# ideai

A fast macOS project browser and code editor with an IntelliJ IDEA-style project
navigator and titlebar project switcher.

Native AppKit, no web view, no Electron. Built for the case where you mostly
*read* and lightly edit code, and want the IDEA layout without the IDEA startup
time or subscription.

## What it does

- **IDEA-style project navigator** — bold project root with its `~`-relative
  path, lazily-loaded directories, per-type file icons, version-control colours
  (added / modified / unversioned / ignored), and a warm tint on build-output
  directories. Fully keyboard-navigable: arrows move and expand, Return opens,
  Space previews, typing jumps to a name. Right-click for open externally,
  reveal in Finder, copy path, rename, or move to trash.
- **Tabs with preview semantics** — a single click in the tree opens a
  provisional tab (shown in italic) that the next click replaces; a
  double-click, Return, or editing pins it. Selecting a file that is already
  open just activates its tab.
- **Binary and oversized files** — open as a tab explaining themselves, with
  buttons to open externally or in a built-in hex viewer, rather than as a
  blocking alert. The hex view memory-maps the file and draws only visible rows,
  so a 100 MB STL opens instantly.
- **Titlebar project switcher** — a coloured project badge and the current git
  branch, both as real `NSToolbar` items on the traffic-light row. The dropdown
  lists open and recent projects with their paths, and supports arrow keys and
  type-to-jump.
- **Recents imported from IDEA** — on first launch, `recentProjects.xml` is read
  from every installed JetBrains IDE, so the switcher is useful immediately.
  Project badge colours carry over too.
- **Editor** — tree-sitter syntax highlighting and code folding for 18
  languages, with editing, undo/redo, multi-caret-free plain selection, IME
  support, and a fixed gutter.
- **Live refresh** — FSEvents watches the tree; `git checkout` in a terminal
  updates the navigator colours.

## Performance

The design goal was that cost scales with the *viewport*, not the file. Measured
on Apple silicon, release build (`swift test -c release --filter PerformanceTests`):

| Operation | File | Time |
|---|---|---|
| Build rope | 7 MB / 200k lines | **11 ms** |
| Keystroke (main thread) | 3.5 MB / 100k lines | **0.013 ms** |
| Highlight one viewport (80 lines) | 3.5 MB / 100k lines | **2.5 ms** |
| 10k random line lookups | 200k lines | **8 ms** |
| Edit cost growth over a 200× larger file | — | **2.8×** |

Three decisions do most of that work:

1. **A persistent rope.** Interior nodes sum UTF-8 bytes, UTF-16 units and
   newlines, so every byte↔UTF-16↔line conversion is O(log n). Because nodes are
   immutable and shared, a `Rope` value is a free snapshot — the background
   parser reads one while typing continues, with no locking and no copy.
2. **Viewport-scoped highlighting.** The syntax query runs only over the byte
   range on screen. Querying a whole large file is the most expensive thing an
   editor can do and it is entirely unnecessary.
3. **The parser is off the main thread.** tree-sitter reparses incrementally —
   it re-reads only ~1 KB after a keystroke — but still rebuilds the root node's
   child list, which is O(siblings) and reaches ~25 ms on a multi-megabyte file.
   The rope is authoritative for text on the main thread; the parser is
   authoritative for colour and is allowed to land a frame late. That is the
   difference between 24.9 ms and 0.013 ms per keystroke.

## Building

```sh
make            # build and launch
make dev        # debug build, run in foreground with logs
make test       # 42 tests
make perf       # performance suite with timings
make install    # copy to /Applications
make help       # all targets
```

Or without make:

```sh
swift build
swift test
Scripts/bundle.sh [debug|release]   # assembles build/ideai.app
```

### Command-line options

Useful for development; `--screenshot` renders the window in-process, so it
works without Screen Recording permission.

```sh
ideai --open <project-dir> [--file <path>] [--expand]
      [--screenshot <out.png>] [--delay <seconds>]
      [--type <text>] [--collapse]
```

## Languages

Swift, Rust, TypeScript, TSX, JavaScript, Python, Go, JSON, Shell, C, C++, Java,
HTML, CSS, YAML, TOML, Markdown, Svelte, OpenSCAD.

Adding one is a package dependency plus a line in
`Sources/IdeaiKit/Syntax/LanguageRegistry.swift`. Grammars ship their own
`highlights.scm`; folding uses `folds.scm` when present and otherwise derives
regions structurally from the tree, so every language folds.

### Vendored grammars

Four grammars live in `Sources/Grammars/` instead of being package
dependencies. Their upstream manifests gate the external scanner behind:

```swift
if FileManager.default.fileExists(atPath: "src/scanner.c") { … }
```

That path is relative, and SPM does not evaluate manifests with the package
checkout as the working directory, so the check is always false, the scanner is
silently dropped, and the grammar fails to link with undefined
`tree_sitter_<lang>_external_scanner_*` symbols. Vendoring lets the source list
be stated explicitly — which also matters for YAML, whose scanner spans five
`.c` files. Run `Scripts/vendor-grammars.sh` to refresh them.

## Layout

```
Sources/IdeaiKit/     engine — rope, syntax, folding, git, project model (no view code)
  Text/               Rope, TextDocument, FoldingState
  Syntax/             LanguageRegistry, SyntaxEngine, HighlightKind
  Git/                GitRepository
  Project/            Project, FileNode, RecentProjects, FileSystemWatcher
Sources/ideai/        AppKit — window, navigator, titlebar, code view
Sources/Grammars/     vendored tree-sitter grammars
```

`IdeaiKit` is free of view code so the engine is testable without a window.

## Known gaps

- No search and no go-to-definition.
- The left tool strip is decorative apart from the project toggle.
- The theme is a fixed dark palette; there is no light mode or theme picker.
- The titlebar pills sit inside macOS 26's rounded toolbar-item capsule. There
  is no opt-out: `NSToolbarItemStyle` offers only plain and prominent. Removing
  the toolbar removes the capsule but also drops the window to the old, smaller
  corner radius, and an empty toolbar plus a titlebar accessory reserves a
  second titlebar row. The capsule is the least-bad option.
- The hex viewer is read-only.
