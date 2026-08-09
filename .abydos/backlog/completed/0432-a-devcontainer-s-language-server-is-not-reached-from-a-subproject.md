# 432. A devcontainer's language server is not reached from a subproject

Two faults found while building the `python-language-server` example, both in
the seam between a devcontainer's language servers and the editor asking them
something. Neither was fixed when found — the files belonged to another agent
at the time — and both are reproducible with that example.

**The request is looked up under the wrong project.** Opened directly, the
example works: pyright starts in the container and a go-to-definition comes back
naming this machine's path. Opened the way that repository is meant to be
opened — `--open abydos-examples --subproject devcontainers/python-language-server`
— pyright still starts correctly *inside the container*, and then the request is
looked up under the top-level project and goes unanswered:

    no python server for abydos-examples: definition unanswered

This is the mirror of what 0424 already fixed for `hasDevContainer`, which asked
`project?.root` and ignored `subprojectRoot` — so the menu could not see a
subproject's devcontainer. The same asymmetry, one layer along: the server is
started for the subproject and looked for under the project. Worth checking
every table keyed by "the project" in `LanguageService` and `LanguageServers`
for the same question, rather than fixing the one path that was noticed.

**The missing-server banner is never withdrawn.** It is raised while the
container is still starting — correctly, since nothing is answering yet — and it
is still on screen sixty seconds later, above a file the container's pyright is
answering about. Photographed. `Sources/AbydosApp/Editor/LanguageService.swift`
raises it; nothing lowers it when a server arrives late, which is exactly what a
container makes normal: a devcontainer's server is minutes away on a cold pull
and a second away afterwards, where a host server was always either there or not.

Both are in the same seam, which is why they are one item.

## What both came to, 2026-08-09

### The scope is one property, and everything reads it

`Project.scopeRoot` — the subproject when there is one, the whole checkout
otherwise. That is the same answer 0424 gave `devContainerRoot` for the same
asymmetry a layer up, and for the same reason: two roots one property apart
will drift again unless there is only one of them to read.

Every `LanguageService` call site takes it. The editor's `opened`, `changed`,
`saved`, `closed`, completion and go-to-definition all passed `project.root`
while `applyScope` passed the scope to `warmUp`, which is the whole fault in
one line. The window's `serverStatus`, `workspaceSymbols`, `documentSymbols`,
find-usages and **the Java debug adapter** took it too — that last one had the
same fault and nobody had hit it, because the adapter lives inside the language
server and `startJavaDebugAdapter` was asking the repository above the module.
`load(project:)` also clears `project.scope`, since the switcher can hand back a
`Project` that was open before with the scope it had then still on it.

**Every table in `LanguageService` and `LanguageServers` was read for the same
question**, and this is what they came to:

| table | keyed by | verdict |
|---|---|---|
| `servers`, `unavailable`, `lastStandardError`, `fetching`, `deferredOpens` | `serverKey(project:languageId:)` | right; they were being *given* the wrong project |
| `diagnostics`, `openDocuments` | the file's URI | not about the project |
| `toolImages`, `devcontainerProjects`, `devcontainerSessions`, `devcontainerCommands`, `devcontainerStarting`, `devcontainerWaiting` | the project path | right, and now the scope's path |
| `missingHints` | **the language alone** | wrong, and fixed: keyed by the server, so "pyright is not in this project's devcontainer" is not offered above a file in the next project |
| `failures`, `announced`, `emptied`, `runningNames` | the language, or nothing | left alone, deliberately — each is cleared per project already and none of them decides which server answers. Worth an item if a session with several projects starts crossing them. |
| `workspaceSymbols` and `shutdown`'s `"<path>#"` prefix scan | the project path | consistent again now the keys are the scope's; a subproject's key does not begin with its checkout's, which the new test asserts because the *paths* do |

**`documentServers` is new**, and it is the half of this that is not keying.
A file open when the scope moves has to be closed at the server that had it and
opened at the one that answers now: without it the container's server came up
knowing about no documents at all, and the file somebody was looking at was the
one it had never been told about. `EditorAreaController.rescope` announces every
group's files again on a scope change; `opened` does nothing when the server is
the same one, because a second `didOpen` for a document a server holds is
undefined in the protocol.

`LanguageServerScopeTests` is the regression test, over `LanguageServers` and
`Project` with no window in sight.

### The strip says what is true while a container comes up

`refreshServerBanner` asked `LanguageServers.suggestion`, which asks the file
system whether the server is on this machine — and for a project worked on in a
container that answer is *no* for ever. It asks `LanguageService.notice` now,
which knows the third state a devcontainer makes normal: not here, not missing,
**coming**.

- **Running** — nothing to say, and this is the withdrawal the entry asks for.
  It works however late the server arrives, because the strip is refreshed by
  `ideaiLanguageServersChanged` and that is posted when one lands.
- **Coming** — "Python's language server is starting in this project's
  devcontainer.", an hourglass, and only the ✕. No "How to install", because
  there is nothing to install; no "Ignore for Python", because the answer to
  "not yet" is to wait and a language switched off for ever because a container
  was slow is the wrong bargain. The same sentence covers an image being
  fetched, which is the same shape.
- **Not in the container** — the sentence is about the file that would have to
  carry it, which is what `LanguageService` already had in `missingHints` and
  the strip could not say.

**No second progress report, deliberately.** The steps are already on screen as
toasts from `DevContainers.Progress` — the screenshot of the waiting strip has
"Building abydos-devcontainer:python-…" and "Starting the devcontainer for…"
stacked in the corner behind it — and a terminal opened in the same container
joins that very start and shows the whole of it (`PreparingTerminal`). Two
things counting one build would disagree the first time one of them was slow.
The strip's job is to say why nothing is answering yet, once, and then stop.

### Proved rather than reasoned

Both invocations, against the example, with the image already built:

    --open …/python-language-server --file main.py --definition 17:6
    → DEFINITION-PATH: …/python-language-server/stations/reading.py   (before and after)

    --open <examples> --subproject devcontainers/python-language-server …
    before → no python server for abydos-examples: definition unanswered
             DEFINITION-PATH: …/python-language-server/main.py        (it never moved)
    after  → DEFINITION-PATH: …/python-language-server/stations/reading.py

and `lsp.log` shows the same server in the same place both times —
`pyright-langserver started for python at …/python-language-server [container
exec abydos-devcontainer-… at /workspaces/python-language-server]` — with
"was told about 1 file(s) opened while its image was being fetched", which is
the re-announcement working. The strip was photographed at four seconds saying
the server is starting, and at seventy seconds it is gone with `reading.py` open
in front of it.

---

Its number is where it sits in the queue, not what it is worth doing next.
