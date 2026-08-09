# 424. Open a project in its devcontainer

A project with a `.devcontainer/devcontainer.json` says what it needs to be
worked on: an image or a Dockerfile, a user, ports, environment, commands to run
once it exists. Every editor that reads that file gives somebody a working
checkout without them installing a toolchain. This app reads it nowhere.

The pieces are already here, which is why this is worth doing rather than
enormous. `ContainerPaths` maps a host path to `/workspace` and back, in both
directions, refusing anything outside the project — written for language servers
and exactly what a workspace folder needs. `ToolContainers` names every
container `abydos-…`, sweeps what an earlier run left, and knows a container is
not the process that started it (0406). `ContainerImages` pulls an image once
however many things ask, and says which of four things went wrong (0401).
`LSPClient` already runs a language server *inside* a container and rewrites
every `file:` URI at the edge, proved end to end against a real gopls. A
devcontainer is those parts pointed at the whole project rather than at one
tool.

## What "the Abydos way" means here, and it is most of the design

VS Code opens a **second window** connected to the container, and everything in
it is remote: a second extension host, a second file system, a reconnect when it
drops. That is a large machine, and it exists because VS Code's editor cannot be
in two places at once.

This app does not need it, and should not have it:

- **No new window.** The project opens in the window it is already in. Opening a
  containerised project and a host project is the same gesture, and the window
  says which it is rather than being a different window.
- **Switching is instant.** `switchProject(to:)` already moves between projects
  in one window. A project whose container is running must switch as fast as one
  without — which means the container **stays up between switches**, exactly as
  the PlantUML server now does (0422), with the same naming and reaping that
  made that safe.
- **The files stay on the host.** The checkout is bind-mounted, so the
  navigator, the editor, search, and git all keep working on host paths, at host
  speed, with no remote file system to write. Only the *tools* move inside: the
  terminal, the language server, the run and debug commands, the build.
- **What runs where is visible.** Somebody must be able to see, at a glance,
  that this terminal is inside the container and that one is not. The titlebar
  capsule already names the project and branch; this is the third thing it
  should be able to say.

## The one decision that shapes everything else

**Read `devcontainer.json` ourselves, or shell out to the reference CLI?**

The spec is not small: `image`, `build.dockerfile`/`context`/`args`, `features`
(a package system of its own, with an ordering algorithm), `dockerComposeFile`
with `service` and `runServices`, `workspaceFolder`, `workspaceMount`, `mounts`,
`runArgs`, `containerEnv`, `remoteEnv`, `containerUser`, `remoteUser`,
`updateRemoteUserUID`, `forwardPorts`, `portsAttributes`, `otherPortsAttributes`,
`initializeCommand`, `onCreateCommand`, `updateContentCommand`,
`postCreateCommand`, `postStartCommand`, `postAttachCommand`, `waitFor`,
`shutdownAction`, `overrideCommand`, `userEnvProbe`, `hostRequirements`,
`customizations`, and JSON-with-comments and `${localEnv:…}`/`${containerEnv:…}`
substitution throughout.

- **The CLI** (`@devcontainers/cli`, `devcontainer up --workspace-folder …`) is
  the reference implementation. It handles features, compose, the lifecycle
  commands and the substitutions, and it is what "full support of the vscode
  devcontainer files" actually means, since it is the same code. The cost is a
  Node dependency the app cannot assume — it is not installed on this machine
  right now — and an answer for when it is missing.
- **Our own reader** has no dependency and no version skew, and would be honest
  and small for the common case (`image` or `build.dockerfile`, a user, some
  env, some ports). It becomes a second implementation of somebody else's spec
  the moment `features` or `dockerComposeFile` appears, and features in
  particular is a package manager.

**Recommendation, to be confirmed before anybody starts:** use the CLI when it
is there, and read the file ourselves for the subset that needs no features and
no compose — with the *file* parsed by us either way, because the app needs to
know the workspace folder, the user and the ports whoever built the container.
A project the subset cannot honestly handle should say so and name the reason,
in the register of `ContainerImages.explain`, rather than starting something
half-configured. Refusing loudly is the thing this codebase does well and it
matters more here than anywhere, because a half-built container looks like a
broken editor.

## What has to be decided, and is not decided here

- **Which subsystems move inside on day one.** The terminal is the obvious first
  and the most valuable: a shell in the container is most of what people want.
  Language servers already have the machinery. Run configurations, the debugger,
  and `make` are each their own piece of work.
- **git.** On the host, where the credentials and the signing key are. That is
  almost certainly right, but it must be *stated*, because a terminal inside the
  container will have `git` on its PATH and somebody will use it, and then the
  two disagree about what is staged.
- **Ports.** `forwardPorts` is `-p` on the container we start, which is easy.
  What is not easy is a port already taken on the host, and saying so.
- **The lifecycle commands.** `postCreateCommand` can take minutes. It needs the
  same treatment as an image pull: on screen, once, with what it is doing, and a
  failure that says which command failed rather than dying quietly.
- **When the container stops.** `shutdownAction` says `stopContainer` by
  default. Against that: switching away and back must be instant. Probably keep
  it running and stop on quit, with 0406's sweep as the safety net — but that is
  a decision about somebody's laptop battery and should be made deliberately, and
  probably be a setting.
- **Rebuilding.** Editing `devcontainer.json` has to be able to rebuild without
  restarting the app, and the old container has to go. "Rebuild Container" is
  the command VS Code has and people will look for it.

## Where to start

The first slice worth shipping, in this order, each useful on its own:

1. ~~**Read the file**~~ — done. `DevContainerFile`.
2. ~~**Start and keep one**~~ — done. `DevContainers`.
3. ~~**A terminal inside it**~~ — done. View ▸ New Terminal in Container.
4. **The language servers**, which is mostly pointing existing machinery at this
   container instead of a per-tool one.
5. **Lifecycle commands**, with the progress and the failure messages.

Docker only, per the decision recorded in 0406 and 0422.

## What the first three steps came to, and what was decided doing them

`Sources/AbydosKit/Run/DevContainerFile.swift` reads the file and
`Sources/AbydosKit/Run/DevContainers.swift` starts one and runs things in it.
A project with a `.devcontainer/devcontainer.json` gets an item beside New
Terminal in the View menu, greyed out for the projects that have none, and the
tab it opens is named after the container so that a shell somewhere else does
not look like a shell here.

**The CLI-versus-own-reader question above is still open and was left open.**
What is here is the reader for the subset, written so that a CLI path could be
put beside it: `DevContainers` takes a `DevContainerConfiguration` and knows
nothing about where it came from.

Read: `image`, `build.dockerfile`/`context`/`args`/`target` and the older
`dockerFile`, `name`, `workspaceFolder`, `workspaceMount`, `containerUser`,
`remoteUser`, `containerEnv`, `remoteEnv`, `forwardPorts`, `mounts` (string and
object), `runArgs` — with comments, trailing commas, all three legal locations,
and `${localEnv:VAR}`, `${localEnv:VAR:default}`, `${localWorkspaceFolder}`,
`${localWorkspaceFolderBasename}`, `${containerWorkspaceFolder}` and
`${containerWorkspaceFolderBasename}` resolved. An unknown `${…}` is left as
written, which is what VS Code does and the only answer that cannot corrupt a
value nobody understood.

Refused by name, one sentence each: `features`; `dockerComposeFile`; **the
lifecycle commands**; `${containerEnv:…}`; a file that is not JSON; a file
naming neither an image nor a Dockerfile, or both; a `workspaceMount` that is
not a bind of this project; a `workspaceFolder` outside the mount; a
`forwardPorts` entry that is not a number; and more than one `devcontainer.json`
in the project.

Decisions taken while doing it, each of which could be reversed:

- **The lifecycle commands refuse rather than being ignored.** Step 5 above is
  what lifts this. `postCreateCommand` is where a project runs `go mod download`,
  and a container that came up without it has tools missing for a reason nothing
  on screen explains — which is exactly the "looks like a broken editor" this
  entry is about. Reading `postCreateCommand` and quietly not running it would
  have been the worst of the three options.
- **No idle reaper**, and this is where it parts company with the PlantUML
  server it is otherwise modelled on. That one can go cold because the worst that
  follows is one slow render; a devcontainer has somebody's shell in it. It lives
  until the project is closed or the app exits, with `ToolContainers.removeAll`
  and 0406's sweep behind it. The battery question above is still a question.
- **The workspace folder defaults to `/workspaces/<basename>`**, the reference
  implementation's default rather than `ContainerPaths`' `/workspace`, because
  the published images expect it. The mapping itself is `ContainerPaths`, which
  is also what refuses a `workspaceFolder` outside the mount.
- **The image's command is always replaced** with a keep-alive, as every
  devcontainer tool does. `overrideCommand: false` is not honoured and is not
  refused either, which is a small hole.
- **`forwardPorts` publishes on `127.0.0.1` only.** Every interface is a
  decision nobody made. A port already taken is reported by name from
  `DevContainers.explainStart`, which is half of the "ports" question above —
  the other half, choosing a different port, is not done.
- **A built image stays on the machine** as `abydos-devcontainer:<project>`.
  It is an image, not a container, so 0406's sweep does not apply to it and
  nothing removes it. Rebuilding (above) is where this gets an answer.
- **Nothing is torn down on switching projects**, so switching is as instant as
  the entry asks. Nothing yet moves *into* the container on switching either —
  the terminal is opened deliberately, not automatically.

Proved end to end rather than by reasoning: `DevContainerLiveTests` brings a
container up from a real file, reads a file through the bind mount, writes one
on this side and reads it on that one, types at a shell on a real pty and reads
the answer back, and checks the container is gone afterwards. It skips cleanly
without docker or without the image. In the app, `--devcontainer` opens the tab
the way the menu does; against a scratch project it answered
`IN:/workspaces/devcontainer-probe:dcd19323739f`.

**The next slice is step 4 or step 5.** Step 5 is worth more: it is the largest
of the refusals, `LanguageServers` already has the machinery step 4 needs, and
until the lifecycle commands run there are real projects this cannot open at all.

## Examples to work against, and to ship

The examples repository beside this one (`../ideai-examples`, cloned as
`abydos-examples`) holds nine projects and **not one devcontainer**. It should
hold several, because this is a feature nobody can test by reasoning: a
devcontainer either comes up and gives somebody a shell with the right toolchain
on it, or it does not, and the only way to know is to open one.

They are also the fixtures. A parsing test can be written against a string, but
"does the container come up, does the language server answer inside it, does
switching away and back stay instant" needs a real project, and the screenshot
harness already points at this repository (`make screenshots EXAMPLES=…`).

Worth having, roughly in the order the reader above learns to handle them:

- **The plainest thing that works** — `image: mcr.microsoft.com/devcontainers/go`
  and nothing else. `go-service` already exists and wants a Go toolchain; this is
  four lines in it and proves the whole path end to end.
- **A Dockerfile instead of an image**, with `build.context` and `build.args`,
  since that is the other half of how a container is named and a different code
  path.
- **A `remoteUser` that is not root**, which is where file ownership on the
  bind mount goes wrong and where `updateRemoteUserUID` earns its place.
- **`postCreateCommand`**, doing something slow enough to see — that is the
  progress and failure reporting this entry asks for, and a command that fails
  on purpose is worth one of its own.
- **`forwardPorts`** on the `smart-home-microservice` or `multi-tier` project,
  which already has something worth reaching on a port.
- **`features`**, and **`dockerComposeFile`** with `multi-tier`, which has the
  shape for it — these two are the boundary of the subset above, so having them
  present is what proves the refusal is honest rather than theoretical.

Two things to be careful about. Every image these name is pulled by anybody who
opens the examples, so prefer the small official `devcontainers/*` images and pin
them. And an example whose container cannot be built is worse than no example,
so whatever lands there needs to be in something that runs them — the examples
repository has its own `Makefile`.

**Still none of them.** The first one was meant to land with steps 1 to 3 and did
not: `abydos-examples` had uncommitted work in it at the time — `Makefile`,
`README.md`, `.abydos/.gitignore` and an untracked `plantuml/` — and committing
into somebody else's half-finished tree is not a thing to do on the way past. It
is four lines in `go-service/.devcontainer/devcontainer.json`:

    {
        // What this project is worked on in.
        "name": "Go service",
        "image": "mcr.microsoft.com/devcontainers/go:1.24-bookworm"
    }

Nothing in the subset needs more than that, and the live test does the same
thing against `alpine:3` in a temporary directory in the meantime — which is
why this is a gap in the *examples* rather than a gap in what is proved.

**Not the same thing as the dev pod.** `DevPod.swift` and the chart under
`DevPod/` are a Kubernetes pod somebody works in remotely; this is a container on
the machine in front of them. They will want to share the path mapping and
possibly the terminal plumbing, and they are otherwise different features. Do not
let one grow into the other by accident.

---

Its number is where it sits in the queue, not what it is worth doing next.
