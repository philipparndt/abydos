## Context

Three facts, each read out of the source rather than assumed.

**The editor asks the scope.** `goToDefinition`, `showCompletions`,
`showSignatureHelp`, `hover`, `opened`, `changed` — all pass
`project.scopeRoot`. Thirty-three call sites pass a root; twenty-one call
`LanguageService`.

**A server is only found below that root.** `LanguageServers.resolve` refuses
without `markerDirectory(for:in:)`, which starts at the root it is given, checks
it, then walks its subdirectories breadth-first to a depth of two. There is no
upward walk anywhere in it.

**So the scope decides which language exists.** With the scope on `go-service`
there is no `Package.swift` at or below it, so `resolve` answers nil and no Swift
server starts. Silence rather than a wrong answer, and nothing in the log says
what happened, because nothing went wrong — nobody asked for a Swift server in a
Go module.

The layout that produced the report:

    abydos-examples/
      cadova-models/Package.swift        ← the file being read is in here
      go-service/go.mod                  ← the scope
      multi-tier/go.mod
      smart-home-microservice/go.mod

With no subproject active the search from the repository root finds
`cadova-models/Package.swift` one level down, which is why "activate the right
one, or none" is the workaround somebody has found. The same breadth-first search
is why a Go file in `multi-tier` can be answered by a server rooted at
`go-service`: three modules, first one wins.

## Goals / Non-Goals

**Goals:**

- The server that answers about a file is rooted where that file's project is,
  whatever the scope says.
- One answer to "which root owns this file", used by every call site, so a file
  cannot be opened against one server and asked about through another.
- No server started for a subproject nobody is looking at.

**Non-Goals:**

- Changing what the scope means for anything else. Runs, git, configurations and
  the build's module stay exactly as they are; this is only about which server
  knows a file.
- Cross-project navigation as a feature — following a symbol into a *dependency*
  of another subproject, or into a checkout elsewhere. 0539 covers a toolchain's
  own sources; this is about a file that is plainly inside the project already.
- Starting servers eagerly. See the cost below.

## Decisions

**The root is found by climbing from the file, not by searching down from a
project.** The nearest ancestor directory holding that language's root markers,
stopping at the project root. It is the direction `markerDirectory` does not
have, and it answers the question that was actually being asked — *which project
is this file in* — rather than *what projects does this scope contain*.

Weighed against two others:

- *Fall back to the scope, then to the project root.* Smaller, and it fixes the
  silence: with the scope on `go-service`, fall back to the repository and find
  `cadova-models` one level down. But it leaves the second fault untouched — the
  Go file answered by the wrong module — because the fallback still searches
  downward and still takes the first match. It fixes the symptom that was
  reported and not the one behind it.
- *Ask the server.* sourcekit-lsp will say what workspace a file belongs to.
  That means starting a server to find out which server to start.

**One function, and every call site takes it.** The dangerous half of this is not
the climb but the disagreement: `didOpen` filed under one root and `definition`
asked under another is a server that has never heard of the file, which looks
exactly like the fault being fixed. So the root becomes a property of the open
file — worked out when it is opened, carried with the tab — and the call sites
pass that rather than reaching for the scope. A grep for `scopeRoot` in the
editor should come back empty afterwards.

**Started on demand, never ahead of time.** A server starts when a file that
needs it is opened, which is what already happens; the difference is only which
root it gets. That keeps this inside 0538's budget: opening one Swift file starts
one Swift server, and a checkout of eight subprojects nobody has opened costs
nothing.

**What it costs when somebody does open several.** sourcekit-lsp needed an index
build of 651 files and about two minutes before its first useful answer in a
Cadova package — measured while fixing the completion work. Two Swift packages
open means two of those. That is the honest price of an answer that is right, and
it is paid only for packages somebody is actually reading. The footer already
says which server is answering and `preparing` already says when one is not ready
— both of which become more visible, not less, and both of which are keyed by the
same root and so keep working.

**A file that belongs to no subproject falls back to the project root**, which is
what happens today for every file. Nothing regresses for a repository that is one
project, which is most of them.

## Risks / Trade-offs

- **More servers running at once.** A person moving between four subprojects
  finishes with four. → On demand only, and 0538 is where the budget argument
  lives; if a ceiling is wanted it belongs there rather than here, and it should
  be a stated number rather than an accident of which pill was clicked.
- **The dangerous half is a partial conversion.** One call site still asking the
  scope produces a file the server has not been told about. → Convert them all,
  and leave a test that the root a file is opened with is the root it is asked
  about with.
- **The climb has to stop.** A file outside the project entirely — the editor
  already marks those — must not walk to `/`. → Bounded by the project root, and
  a file outside it keeps today's answer.
- **Two roots for one path when a subproject contains another.** A package inside
  a package is a real layout. → Nearest ancestor wins, which is the same rule
  `markerDirectory` uses on the way down and the one a build system uses.

## What the driven runs showed

Against a scratchpad copy of `abydos-examples`, never the checkout, with the
project asserted on every run.

**The reported case, and the point of the change** — the same file, the same
answer, whatever the pill says:

    scope=go-service  file=main.swift  root=cadova-models
    scope=examples    file=main.swift  root=cadova-models

**The second fault, which answered rather than going silent.** Three Go modules
with the scope pinned to the first for all three runs:

    scope=alpha  file=alpha/main.go  root=alpha
    scope=alpha  file=beta/main.go   root=beta
    scope=alpha  file=gamma/main.go  root=gamma

Each answered by its own module. Before, the downward breadth-first search
returned whichever `go.mod` it reached first, for all three.

**Two Swift packages in one project are two roots**, which is what makes a second
server possible at all:

    cadova-models/Sources/HexKeyHolder/main.swift  root=cadova-models
    tiny-swift/Sources/Tiny/main.swift             root=tiny-swift

**What a second Swift server costs.** Two Swift packages in one project, the
second opened after the first:

    ANSWER outline      3120 ms  4 symbols in main.swift   (load 10.5 over 10 cores)
    ANSWER completion   3120 ms  1 suggestions             (load 10.5 over 10 cores)
    ANSWER definition   3120 ms  main.swift                (load 10.5 over 10 cores)

**3.1 seconds, and the number must be read with its package beside it.** That is
a one-file package, not a Cadova model — the two minutes already measured was an
index build of 651 files. So the honest finding is not "a second server is
cheap": it is that **a sourcekit-lsp costs an index build proportional to its own
package, not a fixed two minutes**. Which is exactly what the ceiling question
below needs, and it argues against counting servers: two servers over two small
packages is nothing like two over two Cadova models.

**The half that must not move, driven rather than read off the diff.** Scope on
`go-service`, a Swift file from `cadova-models` in front, and the run menu asked:

    MENU: here ✓
    MENU: in the cluster

Those are `go-service`'s own configurations, from its `.abydos/run/`. So in one
window, at one moment: the run configurations are the *scope's* and the language
server root is the *file's* — which is the whole claim of this change, and the
proof that separating them did not take the scope away from what it is for.

**Three more call sites found by driving, not by grepping.** The timing verb
`measureFirstAnswerForTesting` asked `documentSymbols`, `completions` and
`definition` of `project.scopeRoot`, and `javaDebugReadinessForTesting` did the
same — testing code, but testing code that would have *measured the wrong
server* and reported silence as the answer. This is precisely the partial
conversion the tasks warn about, and it survived a grep of the editor directory
because it lives in the window controller. The lesson worth keeping: the grep
that finds a conversion's leftovers has to cover every file that asks, not the
directory where the fault was reported.

**A driver fault found on the way, and worth recording.** Two runs of
`--definition` reported nothing at all. `exerciseGoToDefinitionForTesting`
prints without flushing, and a run whose `--lsp-wait` is long enough for
sourcekit-lsp to index a package is ended by the driver's `timeout` rather than
by the app exiting — so the buffer dies with the process. The same is true of
both `EXIT:` reports, which is why `--debug-inspect` printed nothing earlier the
same day. All three now flush. `--lsp-root` was added for this change and does
not need a server at all: the root is read off the disk, so it answers in
seconds rather than after an index build.

## Whether a ceiling on running servers belongs in 0538

Asked because this change makes more of them possible: before, a project ran one
server per language; now it runs one per language *per subproject somebody has
opened a file from*. `abydos-examples` alone holds a Swift package and several Go
modules, so the ceiling worth naming is real rather than theoretical.

**Yes, and the number to put in it is not known yet.** What is known and worth
handing over:

- A server starts only when a file of its language is opened under a root that
  has none. Nothing starts at launch, so the count follows what somebody
  actually opened, not what the checkout contains.
- The expensive one is measured: sourcekit-lsp needed an index build of 651 files
  and about two minutes before its first useful answer in a Cadova package. Two
  Swift packages opened in one session is that cost twice.
- gopls is cheap by comparison and starts in seconds, so a ceiling counted in
  *servers* would treat the two the same when they are not alike at all.
- And a second sourcekit-lsp over a one-file package answered in 3.1 s under
  load 10.5 — measured here. So even within one language the cost is the
  package's, not the server's, which is the strongest argument against a plain
  count.
- Nothing here observed a machine under strain from this. The bound belongs to
  0538 with a measurement behind it, not to a guess made while adding the thing
  that makes it possible.

So: named, with the numbers above, and left to 0538 rather than invented here.

## What was ruled out

Written while doing it.

**Falling back from the scope to the project root.** One line, and it fixes the
reported silence: search downward from the project instead of from the scope, and
the Swift package is found. It leaves the second fault untouched — the downward
search is breadth-first and returns the first `go.mod` of three, so a file in
`smart-home-microservice` goes on being answered by `go-service`. That fault does
not go silent; it answers, which is worse. The climb fixes both because it starts
from the file.

**Keeping `markerDirectory` and adding a depth.** Searching further down finds
more manifests and makes the wrong-module answer more likely, not less. The
problem was never how far it looked but which end it started from.

**A server per subproject at launch.** sourcekit-lsp needed an index build of 651
files and about two minutes before its first useful answer in a Cadova package.
Doing that for every subproject on open would be minutes of a machine spent on
questions nobody asked. Roots are worked out on demand and a server starts when a
file of that language is opened under it.

**Working the root out at every call site.** Twenty of them in the editor and
three more in the window. The root is a directory walk, and the callers include
one per keystroke — but the real reason is correctness rather than cost: twenty
independent answers is twenty chances for two of them to differ, and a file
opened under one root and asked about under another reaches a server that has
never heard of it. That is the fault being fixed, reintroduced by the fix. So
`LanguageService.root` decides it once and the tab carries the answer.

**Moving the scope out of `serverStatus` and `workspaceSymbols`.** Both are
genuinely scope questions — "which servers does what I am working on have", "find
a symbol in what I am working on" — and the proposal said the scope keeps
everything else. Left deliberately, and named here so the next person does not
read them as a missed conversion.

**Deleting the last mention of `scopeRoot` in the editor directory.** One
remains, in the comment on `LanguageService.root` explaining why the scope is not
the answer. A grep that comes back empty was the task; a comment that stops the
next person from putting it back is worth more than a clean grep.

## Open Questions

- Should the scope pill say something when the file in front belongs elsewhere?
  It would explain why the run configurations are for one thing and the
  diagnostics for another. Possibly a job for the footer, which already names the
  server.
- Is there a case for stopping a server whose subproject nobody has open any
  more? It is the other half of the budget question and probably 0538's.
- `markerDirectory`'s downward search stays for the case with no file in hand —
  starting the servers a project evidently needs at open. Whether that should
  also become "one per subproject, lazily" is a separate argument.
