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
  rather than scraped from a rendered screen, and a hook tells the window what
  every Claude Code session on the machine is doing.
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
brew tap philipparndt/abydos
brew trust philipparndt/abydos
brew install --cask abydos
```

**The `trust` step is not optional and not ceremony.** Homebrew 6 refuses to load
a cask from a tap outside its own repositories until you say you trust it —
`Error: Refusing to load cask … from untrusted tap` — and this tap is exactly
that. It is asking whether you trust [philipparndt/homebrew-abydos][tap] to run
code on your machine, which is a fair question and one to answer for yourself
rather than because a README said to. The tap holds one generated file; it is
printed in full in the Releasing section below.

Once trusted, `brew install --cask philipparndt/abydos/abydos` works as a
one-liner too.

To update:

```sh
brew update && brew upgrade --cask abydos
```

`brew update` refreshes the tap and `upgrade` acts on what it found — the first
without the second checks and installs nothing, which is the usual reason a cask
looks stuck a version behind. Trust is remembered, so this is the whole of it
from here on.

The app does not update itself: there is no Sparkle in it, nothing phones home,
and Homebrew is the only thing that will tell you a new version exists.

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

- **Terminal** — a real PTY with a VT100/xterm emulator of its own, and
  libghostty-vt as an optional second engine under the same panel: full colour,
  mouse reporting, the alternate screen, kitty graphics, ligatures, a Metal
  renderer, and a bundled JetBrains Mono Nerd Font so powerline prompts render
  without installing anything. ⌘J opens one. The panel's tabs can *be* tmux's
  windows, so the strip and `tmux list-windows` are the same list, and the
  panel's title bar counts the sessions working and the ones waiting on you.
- **Agents** — ⇧⌘R has an agent review the branch (⇧⌘U the uncommitted
  changes) and report findings over a local MCP server, so they arrive as typed
  data — file, line, severity — and a click jumps to the line. `abydos-hook`
  is a Claude Code hook that tells the window what every session on the machine
  is doing; ⇧⌘A lists them, and a session that needs you is a toast that takes
  one click to reach. A session is a PTY the app owns, so hiding it does not
  kill it.
- **In a cluster** — a launch configuration with one extra key builds for the
  cluster's architecture, pushes into a development pod and runs there, with
  the pod's output in a panel tab. Press debug instead and the debugger stops
  on your breakpoints, in your sources. A project's own Helm chart can be run
  with one of its containers put into development mode.
- **Run and debug** — launch configurations in `.abydos/run`, `.vscode/launch.json`
  imported, Makefile goals, Maven goals, Gradle tasks, Swift package
  executables and tests, Xcode schemes, Bazel targets, Conan commands, and
  entry points found by scanning. Breakpoints with conditions, hit counts and
  log points; stack, variables, inline values and watches, over DAP. A project
  is trusted before anything of its own is executed.
- **Language servers** — completion with detail and parameter hints, problems,
  hover, go-to-declaration, find-usages, rename and code actions for the
  languages that have one. Nothing is bundled; what is missing is named in a
  bar with the one command that installs it — or the server runs in a
  container, from a tool image this repository builds, or inside the project's
  own devcontainer.
- **Editor** — tree-sitter syntax highlighting and code folding for 24
  languages, with editing, an undo tree, IME support, a fixed gutter that
  marks the lines git would see as changed, blame beside the file, the file's
  own indentation, and other occurrences of the selection. Cost scales with
  the viewport, not the file. ⇧⌘P is a palette over every menu action and
  every file path.
- **Project navigator** — bold project root with its `~`-relative path,
  lazily-loaded directories, a second root for the resolved dependencies,
  per-type file icons, version-control colours, and a warm tint on
  build-output directories. An archive opens like a folder. Fully
  keyboard-navigable; FSEvents keeps it live, so a `git checkout` in a
  terminal recolours it.
- **Tabs with preview semantics** — a single click in the tree opens a
  provisional tab (shown in italic) that the next click replaces; a
  double-click, Return, or editing pins it.
- **Git** — status colours, changes, a log page and a commit page, blame,
  branches, tags, worktrees, stash, fetch, pull and push, with a titlebar
  capsule carrying the project and branch. A checkout of submodules is read as
  many repositories and committed across as one act. Pull requests are read
  and reviewed where the code is, through `gh`. A changed picture diffs as two
  pictures. Anything destructive asks first and leaves a backup ref.
- **Secrets** — values in a dotenv file are drawn under a cover from the
  moment it opens; a SOPS file decrypts from the status bar and encrypts on
  save, and a plaintext secret git can see says so.
- **Previews** — Markdown (⇧⌘V), Mermaid, PlantUML and draw.io diagrams,
  Cadova models, 3D models, pictures, video and PDF, beside or instead of
  their source, built only once somebody has looked.
- **Profiler** — CPU, heap, goroutine, block and mutex profiles with a flame
  graph, pointed at a program here or at a pod in the cluster.
- **Hex editor** — a binary or oversized file opens as bytes: a caret and a
  selection over them, a find bar that searches bytes, an inspector that says
  what the bytes at the caret are, an outline of the format for the ones it
  knows (Mach-O, ELF, PE, PNG, ZIP, SQLite, Java class, WebAssembly and more)
  and an entropy curve. It memory-maps the file and draws only visible rows,
  so a 100 MB STL opens instantly.
- **Compare** — any two files or any two folders, on disk or at a commit, on
  one page: the whole of both files side by side with a curve joining each
  change to where it went, the characters that differ marked, *Change n of m*
  to walk them, and the file's history down the edge so any two revisions are
  A and B by clicking. Two folders align by path — different, equal, only on
  one side, ignored — and a row is marked to copy one way or the other, or to
  delete, and *Apply…* does the lot after moving what it overwrites to the
  Trash. From two rows of the tree, a file dropped onto an open file, or
  `abydos-diff a b`, which is also a `git difftool`.
- **Scratches** (⇧⌘N), **word wrap** (⌥⌘Z), and **zoom** (⌘+ / ⌘− / ⌘0) that
  scales the whole interface — every control — rather than only text.
- **The backlog** (⇧⌘B) — what is left to do, as files beside the code, shown
  as a list and a board; an OpenSpec `changes/` directory is shown on the same
  board.

## What is supported

Two tables, because the two questions people actually ask are "can it do X"
and "does it do that for *my* language". Nothing here is aspirational: every
tick is something with a test behind it.

### Features

| | what it does | what it needs |
|---|---|---|
| **Navigator** | project tree with a dependencies root, archives as folders, version-control colours, keyboard-driven, FSEvents-live | — |
| **Editor** | tree-sitter highlighting, folding, word wrap, change marks, blame, indentation, hex editor, markdown preview | — |
| **Search** | find and replace in file (⌘F, ⌘R), project-wide streaming search (⇧⌘F), go to anything (⇧⌘P) | — |
| **Outline** | ⇧⌘O over a file; symbols from the language server, or from the build file's own parser | a server, for source files |
| **Language servers** | completion, problems, hover, go-to-declaration, find-usages, rename, code actions | the server for that language, on the PATH, in a tool image, or in a devcontainer |
| **Run** | launch configurations in `.abydos/run`, `.vscode/launch.json` imported, Makefile goals, Maven goals, Gradle tasks, Swift packages, Xcode schemes, Bazel targets, Conan, Helm charts, entry points found by scanning | the language's own toolchain, and trust |
| **Debug** | breakpoints (conditional, hit counts, log points), stack, variables, inline values, watches — over DAP | Delve, lldb-dap, or jdtls's java-debug |
| **Run in a cluster** | build here, push into a development pod, run it there, follow its output | kubectl, a cluster |
| **Debug in a cluster** | the same pod, held at the first instruction until the debugger arrives | the above, and the pod image for that language |
| **Profiler** | CPU, heap, goroutine, block, mutex and allocation profiles; flame graph; pod profiling | a Go program serving pprof |
| **Git** | status colours, changes, log and commit pages, blame, branches, tags, worktrees, stash, fetch, pull, push, submodules as one working copy, picture diffs, a backup ref before anything destructive | git |
| **Compare** | two files or two folders side by side, on disk or at a commit; curves between the halves, marks inside a changed line, the file's history as A and B; copies between folders applied together, the Trash as the undo | — (`gh` for nothing; git for the history) |
| **Pull requests** | the list of what waits on you, a page of diffs with ticks that die when the file changes, comments against their lines, a review written from the page, a worktree checkout | `gh`, logged in |
| **Secrets** | dotenv values concealed, SOPS files decrypted and re-encrypted in place, a warning when git can see plaintext | sops, for SOPS files |
| **Previews** | Markdown, Mermaid, PlantUML, draw.io, Cadova, 3D models, pictures, video, PDF | — (PlantUML needs its server image) |
| **Terminal** | real PTY, VT100/xterm, optional libghostty-vt engine, Metal renderer, tmux windows as tabs, kitty graphics, bundled Nerd Font | — |
| **Agent review** | ⇧⌘R / ⇧⌘U — an agent reviews the branch or the uncommitted changes and reports findings over MCP as typed data | Claude Code |
| **Running sessions** | ⇧⌘A — every Claude Code session on the machine, what it is doing, and a way to it | `abydos-hook install` |
| **Backlog** | ⇧⌘B — a list and a board over `.abydos/backlog/` or an OpenSpec `changes/` directory | — |

### Languages

*Highlight* and *fold* are the grammar; *outline* is ⇧⌘O without a language
server; *server* is what provides completion, problems and usages; *run* and
*debug* are the play and bug buttons; *cluster* is running and debugging the
same thing in a development pod.

| language | highlight | fold | outline | server | run | debug | cluster |
|---|:--:|:--:|:--:|---|---|---|:--:|
| **Java** | ✓ | ✓ | ✓ | jdtls, or kmp-lsp | Maven, Gradle, `main` methods | java-debug | ✓ |
| **Kotlin** | ✓ | ✓ | — | jdtls¹ | Gradle, `main` functions | java-debug | ✓ |
| **Go** | ✓ | structural | ✓ | gopls | `go run`, Makefile | Delve | ✓ |
| **Swift** | ✓ | ✓ | ✓ | sourcekit-lsp | Swift package, Xcode scheme, Makefile, launch config | lldb-dap | via a make step |
| **Rust** | ✓ | structural | ✓ | rust-analyzer | Makefile, launch config | lldb-dap | ✓ |
| **C / C++** | ✓ | structural | ✓ | clangd | Makefile, Conan, Bazel, launch config | lldb-dap | ✓ |
| **Zig** | ✓ | ✓ | — | — | Makefile, launch config | lldb-dap | ✓ |
| **Odin** | ✓ | ✓ | — | — | Makefile, launch config | lldb-dap | ✓ |
| **Python** | ✓ | structural | ✓ | pyright | Makefile | — | — |
| **TypeScript / TSX** | ✓ | structural | ✓ | typescript-language-server | Makefile | — | — |
| **JavaScript** | ✓ | structural | ✓ | typescript-language-server | Makefile | — | — |
| **Groovy** | ✓ | ✓ | build files² | — | Gradle | — | — |
| **JSON** | ✓ | structural | — | vscode-json-language-server | — | — | — |
| **Shell** | ✓ | structural | — | — | Makefile | — | — |
| **Makefile** | as shell | structural | ✓ targets | — | every goal | Go goals | ✓ |
| **HTML / XML** | ✓ | structural | — | — | — | — | — |
| **OpenSCAD** | ✓ | structural | server | openscad-lsp | — | — | — |
| **PlantUML**³ | — | — | — | plantuml-lsp | — | — | — |
| **CSS**, **YAML**, **TOML**, **Markdown**, **Svelte** | ✓ | structural | — | — | — | — | — |

¹ jdtls answers for `.java`; a Kotlin file is highlighted and folded but not
served, and its `main` functions are still found, run and debugged — the JVM
does not care which language produced the class.

² A `pom.xml` or a Gradle build file has no server and its grammar knows
nothing about modules, so ⇧⌘O over one is answered by that build file's own
parser: modules, plugins, dependencies, properties, tasks.

³ PlantUML has no grammar here — the ones that exist are stale — so a `.puml`
file is plain text with a server behind it and a preview beside it.

"Structural" folding derives regions from any multi-line node in the parse
tree, which covers braces, brackets and indentation. Every language folds; a
`folds.scm` only makes it tidier.

Nothing here is bundled: a language server, a debugger and a build tool are
each large programs with opinions about your toolchain, and the ones already on
the machine are the right ones. What is missing is said in a bar at the top of
the editor, with the one command that installs it. Every language server the
editor offers also has a container image under `ToolImages/`, built here from
its recipe and never fetched from a registry, for a machine that has the
container runtime and not the toolchain.

## Performance

The design goal was that cost scales with the *viewport*, not the file. Measured
on Apple silicon, release build (`make perf`):

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
make test       # the suite (FILTER=name for part of it)
make warnings   # every warning in this repository's own code, and every file over the length ceiling
make timing     # the render bounds, serialised, on a quiet machine
make perf       # performance suite with timings
make profile    # an .app a profiler can actually symbolicate
make install    # copy to /Applications
make install-cli # put the `abydos` commands on the PATH
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

`make warnings` is a verb of its own and not part of `make build` on purpose: an
incremental build reports only the files it recompiled, so a warning is seen
once by whoever happens to be watching and then never again.

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

Each release has its notes in `docs/release-notes-<version>.md`.

### The website

[philipparndt.github.io/abydos-docs](https://philipparndt.github.io/abydos-docs/),
served from its own public repository —
[philipparndt/abydos-docs](https://github.com/philipparndt/abydos-docs) — because
Pages will not serve a site from a private repository without a paid plan.

`docs/index.html` here is the same page, kept so it can be edited beside the
code it describes. It is not what is served: copy it across and push to publish.

```sh
cp docs/index.html ../abydos-docs/ && git -C ../abydos-docs commit -am "…" && git -C ../abydos-docs push
```

One self-contained file — no build step, no dependencies, no external requests
— so `open docs/index.html` renders exactly what visitors get. `make
screenshots` takes the pictures in `docs/images/`.

### Opening from a terminal

```sh
abydos                     # this directory, as a project
abydos ~/dev/thing         # that directory, as a project
abydos notes.md            # that file, in the editor
abydos main.go:214         # …with the cursor on line 214
abydos a.go b.go           # several tabs, the keyboard in the last
```

An instance that is already running takes the path and raises its window
rather than starting a second copy. Typed in one of Abydos's own terminals, the
file opens in the editor of *that* window and the keyboard goes with it — the
pane asks the terminal it is in, over an escape sequence, and falls back to
`open -a` everywhere else.

`abydos-diff a b` puts two files or two folders side by side, in the window
the pane belongs to when typed in one of the app's own terminals and through
`abydos://compare` otherwise. It is a `git difftool` too:

```sh
git config --global diff.tool abydos
git config --global difftool.abydos.cmd 'abydos-diff --wait "$LOCAL" "$REMOTE"'
git config --global difftool.prompt false
git difftool --dir-diff HEAD~3      # one folder diff over everything
```

`--wait` holds the command until Return is pressed, because `--dir-diff`
copies a change back to the working tree only after the tool exits; the app
cannot yet tell the command that the tab was closed, so Return is the signal.

`abydos-icat picture.png` prints a picture on the terminal's character grid
over the kitty graphics protocol, and `abydos-bench` is the DOOM-fire terminal
stress test. `make install-cli` installs all four; `abydos-hook install` wires
the Claude Code hook into `~/.claude/settings.json`.

### Command-line options

Driving the app from a script, for screenshots and for tests: `--screenshot`
renders the window in-process, so it works without Screen Recording
permission.

```sh
Abydos --open <project-dir> [--file <path>] [--trust] [--expand]
      [--screenshot <out.png>] [--delay <seconds>]
      [--type <text>] [--collapse] [--backlog list|board]
```

That is the beginning of a long list — the whole of it is the parser in
`Sources/AbydosApp/LaunchOptions.swift`, and what a driven run is forbidden to
touch on the machine it runs on is `openspec/specs/screenshots`. Drive against
a copy of a project, never a real checkout: the verbs write real preferences
and real files.

### The .abydos folder

A project Abydos has been opened in keeps one folder beside its code:

```
.abydos/
  .gitignore     # commits run/ and backlog/, ignores the rest
  run/           # one file per launch configuration — shared
  backlog/       # what is left to do, and what the project does — shared
  session.json   # which files were open here — this machine only
```

It used to be called `.ideai`; a project that still has one is read from it and
moved across the first time anything is written. `.vscode/launch.json` is read
but never written: what it holds is imported once, and after that the two go
their own ways.

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
`Sources/AbydosKit/Syntax/LanguageRegistry.swift`. Grammars ship their own
`highlights.scm`; folding uses `folds.scm` when present and otherwise derives
regions structurally from the tree, so every language folds.

A grammar that ships no `folds.scm` at all can be given one here, under
`Sources/AbydosKit/Queries/<language>/`. Java and Kotlin have theirs that way —
neither upstream ships one, and structural folding on a Java file offers to
fold every parenthesised expression in it. The grammar's own always wins, so
this never shadows an upstream that catches up.

### Java

Java support is the whole of a project rather than a grammar:

- **jdtls** for completion, problems, go-to-declaration and find-usages, with a
  data directory per project and the JDKs on this machine reported to it, so a
  module targeting 17 is compiled against 17 rather than against whatever the
  server runs on. `brew install jdtls`. **kmp-lsp** is offered as the other
  choice — no build tool is run, so it is up in seconds, and the menu says what
  that trades away.
- **Maven and Gradle** are read directly — `pom.xml` for its modules, plugins
  and dependencies, a Gradle build for the tasks it declares — so their goals
  appear as run configurations and ⇧⌘O over a build file lists what is in it.
  The wrapper wins over anything on the path: a project that pins its build
  tool means it. A project of a thousand modules has its package directories
  compacted in the tree.
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
extension, or the jar named by `ABYDOS_JAVA_DEBUG_PLUGIN`.

### Vendored grammars

Five grammars — CSS, JavaScript, Make, Python and YAML — live in
`Sources/Grammars/` instead of being package dependencies. Their upstream
manifests gate the external scanner behind:

```swift
if FileManager.default.fileExists(atPath: "src/scanner.c") { … }
```

That path is relative, and SPM does not evaluate manifests with the package
checkout as the working directory, so the check is always false, the scanner is
silently dropped, and the grammar fails to link with undefined
`tree_sitter_<lang>_external_scanner_*` symbols. Vendoring lets the source list
be stated explicitly — which also matters for YAML, whose scanner spans five
`.c` files. `make grammars` refreshes them.

Three more things are vendored for the same reason — there is nothing to depend
on. `Vendor/ghostty-vt.xcframework` is libghostty-vt, built from a named ghostty
commit by `Scripts/build-libghostty-vt.sh`, because it has no release and no
package. Mermaid's browser bundle and draw.io's renderer live under
`Sources/AbydosKit/Preview/`, refreshed by `Scripts/vendor-mermaid.sh` and
`Scripts/vendor-drawio.sh`: every command-line Mermaid carries a headless
Chromium, and a 3.6 MB file loaded into a web view does not.

## Layout

```
Sources/AbydosKit/    engine — no view code, so all of it is testable headless
  Text/               Rope, TextDocument, UndoTree, FoldingState, WrapLayout
  Syntax/             LanguageRegistry, SyntaxEngine, SymbolOutline
  Terminal/           PseudoTerminal, TerminalEmulator, GhosttyTerminalEngine, TmuxMirror, ClaudeHook
  Agent/              MCPServer, ReviewSession
  Backlog/            Backlog, BacklogItem, BacklogSpec, BacklogRunner
  OpenSpec/           OpenSpecChange — a change directory read as a card
  Search/             TextSearch, ProjectSearch, SelectionOccurrences
  LSP/                LSPClient, LanguageServers, WorkspaceEdit, Snippet
  Debug/              DAPClient, DebugSession, DebugAdapters, JavaDebug
  Run/                LaunchConfiguration, Makefile, SwiftPackage, XcodeProject, BazelBuild, ConanProject,
                      HelmRelease, DevPod, DevContainers, ToolImages
  Go/, Java/          GoTooling; JavaTooling, MavenProject, GradleBuild
  Git/                GitRepository, GitEstate (submodules), GitBlame, GitDestructive, GitBackup, Sops, DotenvSecrets
  Forge/              GitHubPullRequests, PullRequestCheckout, PendingReview
  Hex/                ByteDocument, ByteSearch, Formats/ (Mach-O, ELF, PE, PNG, ZIP, …)
  Preview/            Mermaid, Drawio, PlantUML, MarkdownSource, and the vendored renderers
  Profiler/           PprofProfile, FlameGraph, Kubernetes
  Archive/            ArchiveIndex — a zip or tar read as a folder
  Project/            Project, FileNode, FileIndex, DependencyTree, FileSystemWatcher, AgentSessions
  Settings/           Settings, Scheme, Schemes/ (the colour schemes)
  Support/            DrivenRun, ClaudeCommand, StallWatch, …
  Text/               …and TextDiff, the line and character diff behind the compare page
Sources/AbydosApp/    AppKit — window, navigator, titlebar, editor, terminal, panel, git, review, hex, compare
Sources/AbydosMain/   main
Sources/AbydosHook/   abydos-hook, the Claude Code hook as a binary of its own
Sources/AbydosBacklog/ abydos-backlog, the backlog from a terminal
Sources/FireBench/    abydos-bench, the terminal stress test
Sources/Grammars/     vendored tree-sitter grammars
Vendor/               libghostty-vt as an xcframework
Resources/Fonts/      bundled JetBrains Mono Nerd Font (OFL)
DevPod/               the development pod: supervisor, chart, image
ToolImages/           a Dockerfile per language server
openspec/             what the program does (specs/) and what is proposed (changes/)
docs/                 the website's page, its pictures, and the release notes
```

`AbydosKit` is free of view code so the engine is testable without a window;
`Tests/AbydosKitTests` is the suite.

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

### The hook

The sessions you did not start from here matter too — the one in tmux from
yesterday, the three an agent fanned out. `abydos-hook` is a Claude Code hook,
a binary of its own because Claude Code runs it several times per tool call and
what it costs to start is most of what it costs. Each event becomes a
distributed notification, and the window turns those into the pill in the
panel's title bar — how many sessions are working, how many are waiting on you
— the list behind ⇧⌘A, and a toast when a session needs an answer, with one
click to get there.

```sh
abydos-hook install    # wire it into ~/.claude/settings.json
abydos-hook status     # say whether it is wired up
abydos-hook remove     # take it back out
```

### The backlog

The other half of working with an agent is having something to hand it. A
backlog of titles is not that, and neither is a chat message describing a task
from memory — so what is left to do lives beside the code, as files, and the
same folder is read by the app, by the command line and by whatever assistant is
installed.

```
.abydos/backlog/
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

`spec/` is the part borrowed from [OpenSpec](https://github.com/Fission-AI/OpenSpec):
a backlog forgets, and once enough items are in `completed/` the only remaining
description of what the program does is the program. An item that changes
behaviour carries a delta — `ADDED`, `MODIFIED`, `REMOVED` — and folding it in
is a step of the work rather than a tidy-up afterwards, so the spec and the code
change in the same commit.

⇧⌘B opens the dashboard: the same folder as a list to read and a board to move
things on, with a card's state shown by the stripe down its left edge. The pane
shows whichever records of work a project keeps: a project that uses OpenSpec
itself, as this repository now does, gets its `openspec/changes/` on the same
board, each change read from its directory — its ticked tasks are its progress,
its state is derived from what is on disk — with the command that starts work
on it offered on the card.

`abydos-backlog` is the same model from a terminal, which is where an agent
works. It ships in the app bundle.

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
