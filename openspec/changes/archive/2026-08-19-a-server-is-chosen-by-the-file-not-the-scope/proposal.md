## Why

Following `Stadium` out of
`abydos-examples/cadova-models/Sources/HexKeyHolder/main.swift` works when the
scope is that package or the whole checkout, and does nothing at all while the
scope is `go-service`. Reported as navigation, and it is every question a server
answers: completion, hover, diagnostics, rename, usages. **A Swift file in front
of somebody gets no Swift server, because the scope pill says Go.**

It is two lines of code and neither is wrong on its own.

Every question the editor asks is asked of the scope:

    LanguageService.shared.definition(url: tab.url, …, project: project.scopeRoot)

and a server only starts where that language's own markers are found *below* the
root it was given:

    guard let root = markerDirectory(for: definition, in: project) else { return nil }

`markerDirectory` searches **downward**, two levels, and never upward from the
file. So with the scope on `go-service` the search for `Package.swift` starts at
`go-service` and goes down; there is none, so no Swift server is started, and
every answer is silence. Nothing is mis-answered and nothing is logged as wrong —
which is why this reads as "it only works when the right subproject is
activated".

**The same line has a second fault behind it.** With no subproject active, the
search takes the first markers it finds breadth-first. `abydos-examples` holds
three `go.mod`s — `go-service`, `multi-tier`, `smart-home-microservice` — so a Go
file in one of them can be answered by a server rooted in another. That one does
not go silent; it answers, from the wrong module.

`scopeRoot`'s own comment says what the scope is for: which launch
configurations there are, which module a build runs in, which tree git acts on.
Those are all questions about *what somebody is working on*. Which server knows
about a file is a question about **the file**, and it was answered with the pill.

Related: 0432 is this family one floor up — a server started for a subproject and
asked for under the repository above it, answering nothing and saying so only in
the log. 0538 is the cost constraint this has to respect.

## What Changes

- **The server asked about a file is the one whose root owns that file.** Found
  by climbing from the file to the nearest directory holding that language's
  markers, bounded by the project, instead of searching downward from whatever
  the scope happens to be.
- **One place decides it.** There are twenty-one call sites asking
  `LanguageService` and thirty-three passing a root; every one of them must agree
  or a file is opened against one server and asked about through another. The
  root becomes a property of the file, worked out once.
- **Several servers coexist, as they already can.** They are keyed by root
  already, and `twoProjectsDoNotShareAServer` says so; what changes is which root
  a file is filed under.
- **Started on demand and no sooner.** A server for a subproject nobody has
  opened a file from is a server nobody needs — which is what keeps this inside
  0538's budget rather than starting one per subproject at launch.
- **The scope keeps everything else.** Runs, git, configurations, the module a
  build uses: unchanged. It stops being the answer to "who knows about this
  file", which it was never claimed to be.
- **Not proposed: a server per subproject at launch.** sourcekit-lsp took two
  minutes and an index build of 651 files to answer its first useful question in
  a Cadova package; doing that for every subproject on open would be minutes of
  the machine for questions nobody asked.

## Capabilities

### New Capabilities
<!-- None. -->

### Modified Capabilities

- `language-servers`: which root a server is started and looked up under. The
  capability already says a server belongs to a project and that two projects do
  not share one; what it does not say is which project a *file* belongs to, and
  that is the gap this closes.

## Impact

- `Sources/AbydosApp/Editor/EditorViewController.swift` — every
  `project.scopeRoot` handed to `LanguageService`: definition, hover,
  completions, signature help, the open and change notifications, rename,
  usages.
- `Sources/AbydosApp/Editor/LanguageService.swift` — `key(project:languageId:)`
  and everything filed under it, including `preparing`, `health` and the footer.
- `Sources/AbydosKit/LSP/LanguageServers.swift` — `markerDirectory` searches
  down; the climb from a file is the missing direction.
- `Sources/AbydosKit/Project/Subprojects.swift` — has `isSubproject(_:)` and
  `find(in:depth:)`, and no "which of these owns this path".
- `.abydos/backlog/spec/language-servers.md`.
- Memory: one server per subproject somebody opens a file from, rather than one
  per project. The bound and what it costs belong in `design.md`.
