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
- **Search** — find in file (⌘F) with match highlighting and wrapping
  navigation, and project-wide search (⇧⌘F) that streams results as it walks,
  prunes excluded directories, and skips binaries.
- **Terminal** — a real PTY with a VT100/xterm emulator: full colour, mouse
  reporting, the alternate screen, and a bundled Nerd Font so powerline prompts
  render without installing anything. ⌘J.
- **Agent code review** (⇧⌘R) — an agent reviews the branch and reports findings
  over a local MCP server, so they arrive as typed data rather than scraped
  text. Click a finding to jump to the line; click Chat to take the same live
  session over.
- **Go** — run, build, test, trace, CPU profile, and debug under Delve.
- **Word wrap** (⌥⌘Z), **markdown preview** (⇧⌘V), and a **hex viewer** for
  binary files.
- **Live refresh** — FSEvents watches the tree; `git checkout` in a terminal
  updates the navigator colours.
- **Zoom** — ⌘+ / ⌘− / ⌘0 scale the whole interface, not just text.

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
make test       # 159 tests
make perf       # performance suite with timings
make install    # copy to /Applications
make install-cli # put the `ideai` command on the PATH
make help       # all targets
```

Or without make:

```sh
swift build
swift test
Scripts/bundle.sh [debug|release]   # assembles build/ideai.app
```

### Opening from a terminal

```sh
ideai                  # this directory
ideai ~/dev/thing      # that project
ideai cmd/app/main.go  # that file, in the repository around it
```

An instance that is already running takes the path and raises its window
rather than starting a second copy.

### Command-line options

Useful for development; `--screenshot` renders the window in-process, so it
works without Screen Recording permission.

```sh
ideai --open <project-dir> [--file <path>] [--expand]
      [--screenshot <out.png>] [--delay <seconds>]
      [--type <text>] [--collapse]
```

### Profiling

`Run ▸ Profile…` (⌃⇧P) opens the profiler on the bottom panel. Point it at a
Go program's pprof endpoint — a port, a host and port, or a URL — and collect:

- CPU over a window, or heap, goroutine, block, mutex and allocation snapshots
- a flame graph, click a frame to zoom into it
- the functions as a table, sorted by what they cost
- clicking a frame searches the project for that function

Nothing is installed into the program under study: it already serves this if
it imports `net/http/pprof`.

`Pod…` profiles a pod in Kubernetes instead: pick it from the cluster and a
`kubectl port-forward` is opened to whichever port the pod declares — an
annotation, a container port called `pprof`, or 6060 by convention, and the
list says which of the three it is.

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
Sources/IdeaiKit/     engine — no view code, so all of it is testable headless
  Text/               Rope, TextDocument, FoldingState, WrapLayout
  Syntax/             LanguageRegistry, SyntaxEngine, HighlightKind
  Terminal/           PseudoTerminal, TerminalEmulator, TerminalScreen
  Agent/              MCPServer, ReviewSession, AgentLauncher
  Search/             TextSearch, ProjectSearch
  Go/                 GoTooling
  Git/                GitRepository
  Project/            Project, FileNode, RecentProjects, FileSystemWatcher
  Settings/           Settings
Sources/ideai/        AppKit — window, navigator, titlebar, editor, terminal, panel
Sources/Grammars/     vendored tree-sitter grammars
Resources/Fonts/      bundled Hack Nerd Font (MIT / Bitstream Vera)
```

`IdeaiKit` is free of view code so the engine is testable without a window.

## Agent integration

The design point is that agent tools are first-class rather than something you
shell out to.

An agent session is a PTY that *ideai* owns, not something a view owns. That one
decision is what makes the rest work: a session can be hidden and shown again,
or handed over for manual takeover, while its process keeps running throughout.

Structured results come over MCP rather than by parsing rendered output. ideai
runs a per-session HTTP MCP server on loopback and launches the agent pointed at
it with `--strict-mcp-config`, so the user's own MCP servers stay out of the
session. The agent calls `report_review_findings` and the UI receives typed
data — file, line, severity, title, detail — incrementally as the work
proceeds. Scraping a TUI would break whenever the tool restyled its output;
this is a contract instead.

Loopback is not access control, so every request must carry a per-session bearer
token.

## Licence

The bundled font and every dependency permit redistribution in an open-source
project. See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for the details
and obligations.

## Known gaps

- No go-to-definition or rename.
- The left tool strip is decorative apart from the project toggle.
- The theme is a fixed dark palette; there is no light mode or theme picker.
- The titlebar pills sit inside macOS 26's rounded toolbar-item capsule. There
  is no opt-out: `NSToolbarItemStyle` offers only plain and prominent. Removing
  the toolbar removes the capsule but also drops the window to the old, smaller
  corner radius, and an empty toolbar plus a titlebar accessory reserves a
  second titlebar row. The capsule is the least-bad option.
- The hex viewer is read-only.
