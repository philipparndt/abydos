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

---

Its number is where it sits in the queue, not what it is worth doing next.
