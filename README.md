# Abydos

A terminal-first IDE for AI and cloud development, on macOS.

The terminal is not a strip at the bottom of an editor here. It is where the
work happens — shells, tmux windows, agents, a program running in a pod — and
the editor, the debugger and the cluster arrange themselves around it. Native
AppKit: no web view, no Electron, no subscription.

Two things follow from that, and they are what this is for:

- **Agents are first-class.** A session is a PTY the app owns, not something a
  view owns, so it can be hidden, shown, or handed over for manual takeover
  while its process keeps running. Findings arrive over MCP as typed data
  rather than scraped from a rendered screen.
- **The cluster is where the program runs — and where you debug it.** Build
  here, push into a development pod that has the real chart's config, secrets,
  service account and sidecars, and run it there: about a second, against the
  minutes an image build and a rollout cost. Then press debug and stop on a
  breakpoint *in the pod*, in your own sources, because the binary was compiled
  on this machine. Go, Java, Rust, C, C++, Zig and Odin.

[The website](https://philipparndt.github.io/abydos-docs/) ·
[Releases](https://github.com/philipparndt/abydos/releases) ·
[What is supported](#what-is-supported)

## Install

```sh
brew install --cask philipparndt/abydos/abydos
```

That taps [philipparndt/homebrew-abydos][tap] and installs from it in one step;
`brew tap philipparndt/abydos` first and then `brew install --cask abydos` is the
same thing said twice.

To update:

```sh
brew update && brew upgrade --cask abydos
```

`brew update` refreshes the tap and `upgrade` acts on what it found — the first
without the second checks and installs nothing, which is the usual reason a cask
looks stuck a version behind. The app does not update itself: there is no Sparkle
in it, nothing phones home, and Homebrew is the only thing that will tell you a
new version exists.

Or take `Abydos-<version>.dmg` from [the releases page][releases] and drag it to
Applications — the same build, and then updating is your business rather than
brew's. Either way it is signed with a Developer ID and notarised, so Gatekeeper
opens it without a detour through System Settings. Requires macOS 14 or newer.

```sh
brew uninstall --cask abydos          # remove it
brew uninstall --zap --cask abydos    # and its settings and saved state
```

[tap]: https://github.com/philipparndt/homebrew-abydos
[releases]: https://github.com/philipparndt/abydos/releases

## What it does

- **Terminal** — a real PTY with a VT100/xterm emulator: full colour, mouse
  reporting, the alternate screen, kitty graphics, and a bundled Nerd Font so
  powerline prompts render without installing anything. ⌘J opens one; ⌘⏎ gives
  it the whole window. The panel's tabs can *be* tmux's windows, so the strip
  and `tmux list-windows` are the same list.
- **Agents** — ⇧⌘R has an agent review the branch and report findings over a
  local MCP server, so they arrive as typed data — file, line, severity — and
  a click jumps to the line. Chat takes the same live session over. The session
  is a PTY the app owns, so hiding it does not kill it.
- **In a cluster** — a launch configuration with one extra key builds for the
  cluster's architecture, pushes into a development pod and runs there, with
  the pod's output in a panel tab. Press debug instead and the debugger stops
  on your breakpoints, in your sources. Go, Java, Rust, C, C++, Zig and Odin.
- **Run and debug** — launch configurations in `.Abydos/run`, `.vscode/launch.json`
  imported, Makefile goals, Maven goals, Gradle tasks, and entry points found by
  scanning. Breakpoints with conditions, hit counts and log points; stack,
  variables and watches, over DAP.
- **Language servers** — completion, problems, hover, go-to-declaration and
  find-usages for the languages that have one installed. Nothing is bundled;
  what is missing is named in a bar with the one command that installs it.
- **Editor** — tree-sitter syntax highlighting and code folding for 23
  languages, with editing, undo/redo, IME support, and a fixed gutter. Cost
  scales with the viewport, not the file.
- **Project navigator** — bold project root with its `~`-relative path,
  lazily-loaded directories, per-type file icons, version-control colours, and
  a warm tint on build-output directories. Fully keyboard-navigable. FSEvents
  keeps it live, so a `git checkout` in a terminal recolours it.
- **Tabs with preview semantics** — a single click in the tree opens a
  provisional tab (shown in italic) that the next click replaces; a
  double-click, Return, or editing pins it.
- **Git** — status colours, changes, history, blame, branches, worktrees, stash
  and push, with a titlebar switcher carrying the project badge and branch.
- **Profiler** — CPU, heap, goroutine, block and mutex profiles with a flame
  graph, pointed at a program here or at a pod in the cluster.
- **Binary and oversized files** — open as a tab explaining themselves, with a
  built-in hex viewer that memory-maps the file and draws only visible rows, so
  a 100 MB STL opens instantly.
- **Word wrap** (⌥⌘Z), **markdown preview** (⇧⌘V), and **zoom** (⌘+ / ⌘− / ⌘0)
  that scales the whole interface rather than only text.

## What is supported

Two tables, because the two questions people actually ask are "can it do X"
and "does it do that for *my* language". Nothing here is aspirational: every
tick is something with a test behind it.

### Features

| | what it does | what it needs |
|---|---|---|
| **Navigator** | project tree, version-control colours, keyboard-driven, FSEvents-live | — |
| **Editor** | tree-sitter highlighting, folding, word wrap, hex viewer, markdown preview | — |
| **Search** | find in file (⌘F), project-wide streaming search (⇧⌘F) | — |
| **Outline** | ⇧⌘O over a file; symbols from the language server, or from the build file's own parser | a server, for source files |
| **Language servers** | completion, problems, hover, go-to-declaration, find-usages | the server for that language |
| **Run** | launch configurations in `.Abydos/run`, `.vscode/launch.json` imported, Makefile goals, Maven goals, Gradle tasks, entry points found by scanning | the language's own toolchain |
| **Debug** | breakpoints (conditional, hit counts, log points), stack, variables, watches — over DAP | Delve, LLDB, or jdtls's java-debug |
| **Run in a cluster** | build here, push into a development pod, run it there, follow its output | kubectl, a cluster |
| **Debug in a cluster** | the same pod, held at the first instruction until the debugger arrives | the above, and the pod image for that language |
| **Profiler** | CPU, heap, goroutine, block, mutex and allocation profiles; flame graph; pod profiling | a Go program serving pprof |
| **Git** | status colours, changes, history, blame, branches, worktrees, stash, push | git |
| **Terminal** | real PTY, VT100/xterm, tmux windows as tabs, bundled Nerd Font | — |
| **Agent review** | ⇧⌘R — an agent reviews the branch and reports findings over MCP as typed data | Claude Code |

### Languages

*Highlight* and *fold* are the grammar; *outline* is ⇧⌘O without a language
server; *server* is what provides completion, problems and usages; *run* and
*debug* are the play and bug buttons; *cluster* is running and debugging the
same thing in a development pod.

| language | highlight | fold | outline | server | run | debug | cluster |
|---|:--:|:--:|:--:|---|---|---|:--:|
| **Java** | ✓ | ✓ | ✓ | jdtls | Maven, Gradle, `main` methods | java-debug | ✓ |
| **Kotlin** | ✓ | ✓ | — | jdtls¹ | Gradle, `main` functions | java-debug | ✓ |
| **Go** | ✓ | structural | ✓ | gopls | `go run`, Makefile | Delve | ✓ |
| **Swift** | ✓ | ✓ | ✓ | sourcekit-lsp | Makefile, launch config | LLDB | via a make step |
| **Rust** | ✓ | structural | ✓ | rust-analyzer | Makefile, launch config | LLDB | ✓ |
| **C / C++** | ✓ | structural | ✓ | clangd | Makefile, launch config | LLDB | ✓ |
| **Zig** | ✓ | ✓ | — | — | Makefile, launch config | LLDB | ✓ |
| **Odin** | ✓ | ✓ | — | — | Makefile, launch config | LLDB | ✓ |
| **Python** | ✓ | structural | ✓ | pyright | Makefile | — | — |
| **TypeScript / TSX** | ✓ | structural | ✓ | typescript-language-server | Makefile | — | — |
| **JavaScript** | ✓ | structural | ✓ | typescript-language-server | Makefile | — | — |
| **Groovy** | ✓ | ✓ | build files² | — | Gradle | — | — |
| **JSON** | ✓ | structural | — | vscode-json-language-server | — | — | — |
| **Shell** | ✓ | structural | — | — | Makefile | — | — |
| **Makefile** | as shell | structural | ✓ targets | — | every goal | Go goals | ✓ |
| **HTML / XML** | ✓ | structural | — | — | — | — | — |
| **OpenSCAD** | ✓ | structural | server | openscad-lsp | — | — | — |
| **CSS**, **YAML**, **TOML**, **Markdown**, **Svelte** | ✓ | structural | — | — | — | — | — |

¹ jdtls answers for `.java`; a Kotlin file is highlighted and folded but not
served, and its `main` functions are still found, run and debugged — the JVM
does not care which language produced the class.

² A `pom.xml` or a Gradle build file has no server and its grammar knows
nothing about modules, so ⇧⌘O over one is answered by that build file's own
parser: modules, plugins, dependencies, properties, tasks.

"Structural" folding derives regions from any multi-line node in the parse
tree, which covers braces, brackets and indentation. Every language folds; a
`folds.scm` only makes it tidier.

Nothing here is bundled: a language server, a debugger and a build tool are
each large programs with opinions about your toolchain, and the ones already on
the machine are the right ones. What is missing is said in a bar at the top of
the editor, with the one command that installs it.

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
make test       # the suite
make perf       # performance suite with timings
make profile    # an .app a profiler can actually symbolicate
make install    # copy to /Applications
make install-cli # put the `Abydos` command on the PATH
make help       # all targets
```

Or without make:

```sh
swift build
swift test
Scripts/bundle.sh [debug|release]   # assembles build/Abydos.app
```

`make` uses `xcrun swift` rather than whichever `swift` is first on the `PATH`:
a toolchain manager such as swiftly puts its own in front, pinned to a release
older than the SDK, and every target then fails with "this SDK is not supported
by the compiler" rather than anything about this program.

### Profiling

Build with `make profile` before pointing `sample`, `atos` or Instruments at
the app. An ordinary build cannot be symbolicated: `Scripts/pin-uuid.py` gives
every local build the same `LC_UUID` so that macOS keeps its Local Network
grant across rebuilds, and that UUID is also how the profiling tools decide
whose symbols to print. They do not report a mismatch — they print another
build's function names, from this repository, with source files and line
numbers, in call chains that never happened.

`make profile` builds release without the pin and then runs
`Scripts/symbol-check.sh`, which asks `atos` about the address the binary's own
symbol table gives for `main` and refuses to be quiet when the answer is
something else. `make symbol-check` asks the same question of a build you
already have.

`make perf` and `make scale` need none of this: they measure a test binary
SwiftPM links, which is never pinned.

### Releasing

```sh
make sign-check                     # the identity and notary profile it will use
make release                        # sign, notarise, package build/Abydos-<version>.dmg
make release-publish VERSION=0.2.0  # all of that, tagged and uploaded to GitHub
make tap VERSION=0.2.0              # point the Homebrew tap at a release
```

`release-publish` does the whole thing in the one order that keeps the tag and
the download honest: it stamps `CFBundleShortVersionString`, commits that, tags
`v0.2.0`, builds *from* the tag — so the commit stamped into the bundle is the
one the tag names — signs, notarises, writes a `.sha256` beside the image,
pushes, creates the GitHub release with both files attached, and last of all
points the Homebrew tap at it. It refuses a dirty working tree, an existing tag,
a missing Developer ID certificate, and a `gh` that is not logged in.

The tap is [philipparndt/homebrew-abydos][tap], and the cask it carries is three
facts — a version, a checksum and a URL — generated from the release rather than
edited by hand. It is updated *after* the release exists, because a cask naming
a download GitHub does not have yet is a `brew install` that fails for whoever
is quickest. `make tap` runs that step on its own, which is what to use when the
release went out fine and only the tap needs fixing:

```sh
Scripts/update-tap.sh --print 0.2.0 <sha256>   # the cask, without publishing it
```

The credentials are a keychain profile, stored once:

```sh
xcrun notarytool store-credentials notarytool \
    --apple-id <Apple ID> --team-id <team> --password <app-specific password>
```

### The website

[philipparndt.github.io/Abydos-docs](https://philipparndt.github.io/Abydos-docs/),
served from its own public repository —
[philipparndt/abydos-docs](https://github.com/philipparndt/abydos-docs) — because
Pages will not serve a site from a private repository without a paid plan.

`docs/index.html` here is the same page, kept so it can be edited beside the
code it describes. It is not what is served: copy it across and push to publish.

```sh
cp docs/index.html ../Abydos-docs/ && git -C ../Abydos-docs commit -am "…" && git -C ../Abydos-docs push
```

One self-contained file — no build step, no dependencies, no external requests
— so `open docs/index.html` renders exactly what visitors get.

### Opening from a terminal

```sh
Abydos                  # this directory
Abydos ~/dev/thing      # that project
Abydos cmd/app/main.go  # that file, in the repository around it
```

An instance that is already running takes the path and raises its window
rather than starting a second copy.

### Command-line options

Useful for development; `--screenshot` renders the window in-process, so it
works without Screen Recording permission.

```sh
Abydos --open <project-dir> [--file <path>] [--expand]
      [--screenshot <out.png>] [--delay <seconds>]
      [--type <text>] [--collapse] [--backlog list|board]
```

### The .Abydos folder

A project Abydos has been opened in keeps one folder beside its code:

```
.Abydos/
  .gitignore     # commits run/ and backlog/, ignores the rest
  run/           # one file per launch configuration — shared
  backlog/       # what is left to do, and what the project does — shared
  session.json   # which files were open here — this machine only
```

`.vscode/launch.json` is read but never written: what it holds is imported
once, and after that the two go their own ways.

### Make goals

The run menu lists the goals of the project's Makefiles that start a Go
program. Choosing one writes a launch configuration that:

- runs everything the goal builds **except** the Go binary, through make
- lets the debugger build the Go package itself, since a binary linked with
  `-ldflags "-s -w"` has no symbols to debug
- passes the arguments the recipe passes, and sets the environment it sets —
  including `VAR=$(...)` assignments, which are evaluated in a login shell at
  launch, so a password out of `sops` still reaches the program

The extra keys are `Abydos.make` and `Abydos.envCommands`; anything else reading
`launch.json` ignores them.

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
Kotlin, Groovy, HTML, XML, CSS, YAML, TOML, Markdown, Svelte, OpenSCAD, Odin,
Zig.

Adding one is a package dependency plus a line in
`Sources/IdeaiKit/Syntax/LanguageRegistry.swift`. Grammars ship their own
`highlights.scm`; folding uses `folds.scm` when present and otherwise derives
regions structurally from the tree, so every language folds.

A grammar that ships no `folds.scm` at all can be given one here, under
`Sources/IdeaiKit/Queries/<language>/`. Java and Kotlin have theirs that way —
neither upstream ships one, and structural folding on a Java file offers to
fold every parenthesised expression in it. The grammar's own always wins, so
this never shadows an upstream that catches up.

### Java

Java support is the whole of a project rather than a grammar:

- **jdtls** for completion, problems, go-to-declaration and find-usages, with a
  data directory per project and the JDKs on this machine reported to it, so a
  module targeting 17 is compiled against 17 rather than against whatever the
  server runs on. `brew install jdtls`.
- **Maven and Gradle** are read directly — `pom.xml` for its modules, plugins
  and dependencies, a Gradle build for the tasks it declares — so their goals
  appear as run configurations and ⇧⌘O over a build file lists what is in it.
  The wrapper wins over anything on the path: a project that pins its build
  tool means it.
- **Debugging** goes through java-debug, which is not a program but a bundle
  the language server loads: jdtls is asked to start a debug session, answers
  with a port, and the rest is ordinary DAP. The classpath comes from the same
  server, because nothing else knows it.
- **In a cluster**, a jar is built here and pushed into a development pod that
  has a JVM in it (the `-jvm` image variant). Debugging starts that JVM with
  JDWP open and suspended, so the attach lands before the program has done
  anything.

The debug bundle is the one piece with nowhere standard to live. Any of these
is found: `~/.local/share/java-debug/`, Mason's
`java-debug-adapter/extension/server/`, VS Code's `vscjava.vscode-java-debug`
extension, or the jar named by `IDEAI_JAVA_DEBUG_PLUGIN`.

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
  Backlog/            Backlog, BacklogItem, BacklogSpec, BacklogRunner
  Search/             TextSearch, ProjectSearch
  Go/                 GoTooling
  Java/               JavaTooling, MavenProject, GradleBuild
  Git/                GitRepository
  Project/            Project, FileNode, RecentProjects, FileSystemWatcher
  Settings/           Settings
Sources/Abydos/        AppKit — window, navigator, titlebar, editor, terminal, panel
Sources/Grammars/     vendored tree-sitter grammars
Resources/Fonts/      bundled Hack Nerd Font (MIT / Bitstream Vera)
```

`IdeaiKit` is free of view code so the engine is testable without a window.

## Agent integration

The design point is that agent tools are first-class rather than something you
shell out to.

An agent session is a PTY that *Abydos* owns, not something a view owns. That one
decision is what makes the rest work: a session can be hidden and shown again,
or handed over for manual takeover, while its process keeps running throughout.

Structured results come over MCP rather than by parsing rendered output. Abydos
runs a per-session HTTP MCP server on loopback and launches the agent pointed at
it with `--strict-mcp-config`, so the user's own MCP servers stay out of the
session. The agent calls `report_review_findings` and the UI receives typed
data — file, line, severity, title, detail — incrementally as the work
proceeds. Scraping a TUI would break whenever the tool restyled its output;
this is a contract instead.

Loopback is not access control, so every request must carry a per-session bearer
token.

### The backlog

The other half of working with an agent is having something to hand it. A
backlog of titles is not that, and neither is a chat message describing a task
from memory — so what is left to do lives beside the code, as files, and the
same folder is read by the app, by the command line and by whatever assistant is
installed.

```
.Abydos/backlog/
  AGENTS.md      the workflow, one page — every tool's own file points here
  project.md     what this project is, for something that has never seen it
  spec/          what the project does today, one file per capability
  open/          written down, not yet agreed
  ready/         agreed — anybody, or any agent, may start
  in-progress/   being worked on now
  waiting/       stuck on something that is not work
  completed/     done, keeping its number
```

An item is one markdown file, or a folder with `task.md` in it when it carries
a screenshot. Its state is the folder it is in and nothing else, so moving it
along is `git mv` — a change anybody can read in a diff and revert with another
one. Each carries a `## Steps` checklist saying what is done `[x]` and what is
still missing `[ ]`, which is what the fraction and the bar on a card are.

`ready` is the one an agent picks from, and it exists because `open` is a pile:
half of it is a sentence somebody wrote down so as not to forget it, and an
agent that picks one of those spends an afternoon inventing the parts nobody
decided. Nothing moves an item into `ready` automatically.

Picking one up makes a git worktree of its own on `backlog/<number>-<slug>`,
moves the item to `in-progress` on both sides, and starts the assistant there —
a checkout each, because two agents in one working tree is two agents editing
each other's half-finished files.

`spec/` is the part borrowed from [openspec](https://github.com/Fission-AI/OpenSpec):
a backlog forgets, and once enough items are in `completed/` the only remaining
description of what the program does is the program. An item that changes
behaviour carries a delta — `ADDED`, `MODIFIED`, `REMOVED` — and folding it in
is a step of the work rather than a tidy-up afterwards, so the spec and the code
change in the same commit.

⇧⌘B opens the dashboard: the same folder as a list to read and a board to move
things on, with a card's state shown by the stripe down its left edge.

`abydos-backlog` is the same model from a terminal, which is where an agent
works. It ships in the app bundle and `make install-cli` puts it on the PATH.

```
abydos-backlog init            make one here, and ask which assistant works it
abydos-backlog next            the lowest-numbered ready item
abydos-backlog start           worktree, branch, agent
abydos-backlog done <number>   fold the spec delta in, and complete it
```

`init` asks once which assistant this project uses and writes the file that one
reads — a skill and a command for Claude Code, `copilot-instructions.md` and a
prompt for Copilot, `AGENTS.md` for opencode and Codex, a rule for Cursor. All
of them are four lines pointing at `AGENTS.md`, because five copies of a
workflow is five workflows within a month. Running it again is safe: files the
project owns are left alone, and a file it already had keeps everything outside
the fenced section.

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
