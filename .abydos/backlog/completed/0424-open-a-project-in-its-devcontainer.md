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
4. ~~**The language servers**~~ — done. `LanguageServerLaunch.devcontainer`.
5. ~~**Lifecycle commands**~~ — done. `DevContainerLifecycle`.

~~Docker only, per the decision recorded in 0406 and 0422.~~ **Both runtimes,
since 2026-08-09** — except a devcontainer that forwards a port, which is
refused by name on Apple's. See below.

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

Refused by name, one sentence each: `features`; `dockerComposeFile`;
~~**the lifecycle commands**~~ (lifted, see below); `${containerEnv:…}`; a file
that is not JSON; a file
naming neither an image nor a Dockerfile, or both; a `workspaceMount` that is
not a bind of this project; a `workspaceFolder` outside the mount; a
`forwardPorts` entry that is not a number; and ~~more than one
`devcontainer.json` in the project~~ (lifted, see below — they are offered).

Decisions taken while doing it, each of which could be reversed:

- ~~**The lifecycle commands refuse rather than being ignored.**~~ Lifted; step
  5 below is what came of it. `postCreateCommand` is where a project runs `go mod download`,
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

### Later: Apple's runtime opens one too, 2026-08-09

The refusal above was inherited from 0406, and its reason — that a container
kept for a whole editing session most needs removing again, and that verb was
unproven — is gone: `container rm --force` is proven end to end there now, and
so is the sweep that catches what a crash leaves. Every other piece a
devcontainer is made of was then exercised on Apple's runtime rather than
reasoned about, by running `DevContainerLiveTests` against it: the bind mount
with a file written on the host and read inside, `-d` with the keep-alive,
`--entrypoint /bin/sh`, `-u`, `-e` on both sides of the `container`/`remote`
split, `-w`, and `exec -it` onto a real pty with a prompt that answered. So
`DevContainers.canStart` is true for both.

**One thing is refused, by name: `forwardPorts`.** A port published to the host
does not work on Apple's runtime — it is listened on, the connection is
accepted, and then it is reset, because the runtime's own forwarder cannot reach
the container behind it (`No route to host` in its log; macOS's local-network
privacy, which refuses the helper the same way it refuses this app). A project
naming `forwardPorts` is naming the thing it wants reachable, so starting it and
saying nothing would be exactly the "half-built container looks like a broken
editor" this entry is about. `DevContainers.unsupported` is the sentence, and it
names the ports and says to choose Docker. A devcontainer with no `forwardPorts`
is not stopped.

Two smaller things had to change to make this true rather than nearly true:

- **`stateCommand` was docker's `inspect -f {{.State.Running}}`.** Apple's
  `inspect` has no `--format` at all; it prints the whole record as JSON.
  `DevContainers.isRunning` reads it, rather than searching the text for "true",
  which an image reference could have supplied.
- **`explainStart` said "Docker is not running"** whatever the runtime was. It
  is named now, so nobody is sent to start the wrong thing.

`ContainerImages.inspect`/`.pull` were also sending Apple's runtime a
subcommand that does not exist, so no image-backed feature had ever worked
there; that is 0406's note, and it had to be fixed before any of this could be
tried.

Proved end to end rather than by reasoning: `DevContainerLiveTests` brings a
container up from a real file, reads a file through the bind mount, writes one
on this side and reads it on that one, types at a shell on a real pty and reads
the answer back, and checks the container is gone afterwards. It skips cleanly
without docker or without the image. In the app, `--devcontainer` opens the tab
the way the menu does; against a scratch project it answered
`IN:/workspaces/devcontainer-probe:dcd19323739f`.

~~**The next slice is step 4 or step 5.**~~ Both are done; what each came to is
below.

## What steps 5 and 4 came to, 2026-08-09

### Step 5: the lifecycle commands run

All six, each at its own moment. `Sources/AbydosKit/Run/DevContainerLifecycle.swift`
is what they are — `DevContainerStage` (the field name is the raw value, because
every message about one names the field somebody would go and edit) and
`DevContainerCommand`, which is the three shapes the spec gives them: a string
run through `/bin/sh -c`, an array run as argv with no shell between, and an
object of named commands **run in parallel**, which is what the spec says of it.
`DevContainers.runLifecycle` is what runs them, and the refusal above is gone.

**"Has this container been created already?" is a marker file inside the
container**, at `/tmp/.abydos-devcontainer`. Not on the bind mount and not in
`.abydos/`, and the reason is the whole of the decision: the question is about
*this container*, not about the project, and the only thing whose lifetime is
the container's is the container's own writable layer. A marker beside the
checkout survives `docker rm`, so the next container — a rebuild, a machine
restarted, a crash swept up by 0406 — would skip an installer it has never run,
and a container missing its tools with nothing on screen saying so is exactly
the "looks like a broken editor" this entry is about. `/tmp` because it is the
one directory every image has and every user can write to, and because its
lifetime is exactly right: it survives a stop and start, which is not creation,
and dies with the container, which is. **It is written after the three creation
commands have all succeeded**, so a `postCreateCommand` that failed is tried
again next time rather than skipped for ever.

**`initializeCommand` runs, on this machine, and that is a decision about
trust.** It is a command out of somebody's repository executing on their laptop.
It is run for two reasons: the app already runs command lines a project supplies
— a run configuration out of `launch.json`, a `make` target, a build scheme — so
this is the same trust rather than a new one; and a file whose
`initializeCommand` creates the directory its `mounts` bind, which is the common
use, does not work at all without it. What is different is that it is not inside
anything, so it is the one command **named on screen before it runs** rather
than only logged, and it runs only when somebody has asked for the devcontainer
— opening a project does not start one. The real answer is a trust prompt for a
checkout nobody has vouched for, the way VS Code has one; this app has no such
concept, inventing one here would be the wrong place for it, and it is its own
item.

**A failure names the command and its exit status**, in one sentence, and takes
the container with it. `devcontainers/post-create-fails` produces:

> post-create-fails's postCreateCommand exited 3: error: no such package:
> a-package-that-does-not-exist. The container was removed and nothing after it
> was run — fix `sh .devcontainer/post-create.sh` in the devcontainer.json and
> open the project again.

Two things in that are deliberate. The line quoted is the last one on **standard
error**, because a command that fails writes the reason there and its progress
to the other stream — the last line of standard output is "step 3 of 3", which
says how far it got and not what went wrong; `RuntimeCommand.Result` keeps the
two apart for this. And the container is *removed*: a half-installed container
that the next open would find running and reuse is the state this refuses into
existence rather than out of. `postStartCommand` never runs.

**On screen**: one line per command, naming the field and what it is running,
which is `ContainerImages.progressMessage`'s bargain applied to something that
can take minutes. Everything the command printed goes to
`~/Library/Logs/Abydos/devcontainer.log`, because a `postCreateCommand` is the
one thing in this app that can print for ten minutes and a toast per line would
be worse than silence.

**`waitFor` is honoured as a floor rather than as a starting gun**, and that is
the one place this deliberately does less than the spec. The spec has it name
the command after which the container may be handed to somebody, with anything
later still running behind them; VS Code needs that because it has already
opened a window. This app hands the container out at the moment somebody asks to
work in it — a terminal, a language server — so it waits for all of them, which
is never less than the file asked for, and never gives anybody a shell in a
container still installing the toolchain they are about to use. A `waitFor` that
names nothing is refused rather than ignored.

`postAttachCommand` runs per attach: a terminal is one, and a language server
starting is another.

### Step 4: the language servers run inside it

`LanguageServerLaunch.devcontainer` is the new case, and the difference from
`.image` is not how it starts but *whose container it is*. An image is started
for one server and removed with it; a devcontainer belongs to the project, holds
somebody's terminal, and was up before any of this. So **`launch.container` is
nil for it** — that is the one place the two container cases must not agree,
because removing the container when a server stops would take the terminal, the
build and the session with it. What stopping the server has to end is the
server, and the protocol's own `exit` does that from inside; `ContainerLSPLive`'s
successor asserts that no `gopls` is left in the container's `/proc` afterwards,
which is 0427 one floor down.

Three things that hold on this machine do not hold in there, and each was a bug
waiting to be written:

- **The command is not resolved here.** No `xcrun`, no walk of this machine's
  PATH: the server is not on this machine and a path found here names nothing
  there. The bare command goes in and the container's PATH resolves it.
- **The arguments are the definition's own**, not `arguments(for:root:)`, whose
  additions are jdtls's data directory and the Swift indexer's scratch path —
  both directories on this machine.
- **The root and the mapping are the devcontainer's**, which is where the *file*
  said and not `/workspace`.

**Which servers the container has is asked once, of the container**, in one
`command -v` over every server this app knows. Without it, every language the
project touches starts a server that fails its handshake ten seconds later with
the runtime's own `executable file not found`, which says nothing about the
project. A server the container does not have is reported as missing **with a
hint about the file that would have to carry it**, and the copy on this machine
is *not* used instead — that is the same rule an image already has, and the
alternative is the same code getting different answers on two machines.

**A project with a devcontainer this app can honour gets its servers inside it,
and the container is started for them.** That is the largest of these decisions
and the most reversible. It follows from what the entry already says a
devcontainer is: the project stating which toolchain it is worked on with. The
alternative — servers on this machine beside a container that is up — is exactly
0427's "the errors on screen are not the errors from the compiler", one floor up.
Projects with no `devcontainer.json`, which is nearly all of them, are untouched;
a container that will not start falls back to this machine, once, with the reason
said out loud and written down.

**Nothing stops the container when the project closes**, still. The servers in
it go, the way every other server for that project goes; the container lives
until the app exits, which is what the "switching must be instant" decision
above asks for and what `ToolContainers.removeAll` and 0406's sweep stand behind.

### Proved rather than reasoned

`DevContainerLifecycleLiveTests` brings a real container up from a real file and
asks it: the tool `onCreateCommand` installed answers; the three creation
commands ran once in the spec's order and the two members of the object form
overlapped (each waits for the other to appear, so a clock cannot get it wrong);
the marker is there; running the lifecycle again runs `postStartCommand` a second
time and the creation commands *not* at all; two attaches are two
`postAttachCommand`s; `initializeCommand`'s evidence is a file on this side. A
second test drives a `postCreateCommand` that exits 3 and asserts the sentence
and that nothing is left behind. A third runs `devcontainers/post-create` from
the examples repository end to end and finds `jq` — a package the image
deliberately does not carry — inside the container.

`DevContainerLSPLiveTests` opens a Go project whose devcontainer mounts it at
`/src`, `exec`s gopls into it, and gets diagnostics, symbols and a
go-to-declaration back **named as this machine names them**. Then it shuts the
server down and reads the container's `/proc` to prove gopls is gone and the
container is not.

Both of those are docker only, deliberately, while `DevContainerLiveTests` stays
on both: a lifecycle command is `exec` and `RuntimeCommand`, and both are
already exercised on Apple's runtime there. Running the matrix twice more buys
six container creations on the runtime whose service is this suite's known
bottleneck, and no coverage.

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

### Which of them exist now, and what each one is for

Ten, in `abydos-examples`. ~~Five come up and five are refused~~ ~~seven come
up and three are refused, since the lifecycle commands run~~ — **eight come up
and two are refused, since several devcontainers are offered**, and both halves
are the point: a refusal nobody can watch happen is a paragraph, not a promise.
`ExampleDevContainerTests` reads every one of them through `DevContainerFile`
and asserts what it is for — including the exact refusal sentence — so this list
and those files cannot drift apart. It skips when the examples repository is not
beside this one.

| project | what it demonstrates |
|---|---|
| `go-service` | the plainest thing that works: `image` and nothing else |
| `smart-home-microservice` | `forwardPorts` on a service that serves, and `containerEnv` against `remoteEnv` |
| `devcontainers/dockerfile-build` | `build.dockerfile`, `context: ".."`, `args`, `target` — each checkable from inside |
| `devcontainers/non-root-user` | `containerUser` on `run` against `remoteUser` on `exec` |
| `devcontainers/substitutions` | every `${…}` this side can answer, plus `workspaceMount`, `mounts`, `runArgs` |
| `multi-tier` | **refused**: `dockerComposeFile`, beside a compose file that really works |
| `devcontainers/features` | **refused**: `features`, naming the first one found |
| `devcontainers/post-create` | `postCreateCommand`, one slow enough to need reporting — and it installs `jq`, which the image does not carry |
| `devcontainers/post-create-fails` | the same, with a command that exits 3 partway and a `postStartCommand` that must not run after it |
| `devcontainers/two-containers` | ~~**refused**: two `devcontainer.json`, naming both~~ — two menu entries, and both containers up at once |

The five that come up were each brought up, given a shell on a real pty at the
workspace folder the file asked for, and removed. `smart-home-microservice`
answered `200` on `http://127.0.0.1:8080/` from this side while the service ran
inside it, which is `forwardPorts` proved rather than asserted.
`devcontainers/check.sh` in that repository does the same round in one command;
the examples `Makefile` has no goal for it yet, and wants one. **`check.sh` and
its `README.md` still describe the two `post-create` projects as refused**, and
now say something that is no longer true — that repository was read and not
written to here, so somebody has to go and correct it.

`golang:1.24-alpine` (259 MB) rather than `mcr.microsoft.com/devcontainers/go`
(over a gigabyte) for the two Go projects, deliberately: it is the same
toolchain, and anybody who opens an example pulls what it names. The rest are
`alpine:3.21` (8 MB) and `mcr.microsoft.com/devcontainers/base:alpine-3.21`
(735 MB), which is the smallest official image that actually has a `vscode` user
to be non-root as.

**Two things those examples turned up.** `hasDevContainer` asked
`project?.root` and ignored `subprojectRoot`, so a devcontainer belonging to a
*subproject* was invisible to the menu — and `abydos-examples` is the repository
that exists to be opened as subprojects, so not one of these could be opened the
way they are meant to be. **Fixed:** `devContainerRoot` is the subproject's when
it has one and the project's otherwise, and the menu item, the action and the
`--devcontainer` harness all read that one property, so what the menu offers and
what starts cannot disagree. The item is also **named after the container** the
way the tab it opens is — "New Terminal in Built from a Dockerfile ⬢" — because
ten subprojects with a devcontainer each is exactly the case where "Container"
says nothing; the folder is the name when the file has none or is refused.
Proved by opening `abydos-examples` with `devcontainers/dockerfile-build` as the
subproject: the shell came up in `abydos-devcontainer-…` at
`/workspaces/dockerfile-build`. And the `--devcontainer` harness opens whatever
project the app restores rather than the one `--open` names when the app has
saved window state, which is why it now prints the root it actually looked in —
and the container's root beside it.

**Not the same thing as the dev pod.** `DevPod.swift` and the chart under
`DevPod/` are a Kubernetes pod somebody works in remotely; this is a container on
the machine in front of them. They will want to share the path mapping and
possibly the terminal plumbing, and they are otherwise different features. Do not
let one grow into the other by accident.

### Later: several devcontainers are offered rather than refused, 2026-08-09

**"More than one `devcontainer.json`" is no longer a refusal.** It was one for a
single reason, written down above — picking the first quietly would be picking
somebody's toolchain for them, and there was nowhere to ask which one they
meant. There is now: the terminal panel's `+` grew a chevron this afternoon, and
a menu is exactly where a question like that belongs. So `.devcontainer/alpine`
beside `.devcontainer/go` gets two entries and somebody picks one.

**Each entry names its own container**, and that is the load-bearing part rather
than a nicety: the two share a project, a checkout, a mount and a workspace
folder, so if they cannot name themselves apart, a menu offering both says less
than the refusal it replaced. `DevContainerFile.name(of:in:)` is the rule — the
file's own `name`, and **the folder it sits in when it has none**, so
`.devcontainer/go` is "go". A file that is *refused* still gets named, out of its
raw `name` field, because a refusal attributed to nothing on screen is worse than
no refusal. The two fixed locations have no folder of their own and fall back to
the project, which is what a project with one devcontainer has always shown —
that case does not move.

`devcontainers/two-containers` answers:

```
New Terminal | New Terminal in Small ⬢ | New Terminal in With a Go toolchain ⬢
```

**A session is now kept against the file rather than against the project**, and
that was the one real bug in the way. `DevContainers.sessions` was keyed on the
project path, so the second container asked for would have been handed the
first's — the same name, the wrong image, and the second `run` never happening.
Keyed on the canonical file, two containers for one project are two containers.
Nothing else about reaping needed changing and that is worth saying: a
devcontainer already has no idle reaper (the decision above, because it holds
somebody's shell), `ToolContainers.mint` already gives every container its own
name, 0406's sweep is by prefix and owning pid, and `stop(project:)` — which is
what closing a project calls — now removes every one of them rather than one.

**The View menu's item opens the first, and says which one that is.** It is one
command with one title and the alternative was a submenu; a submenu costs the
two things that make the ordinary case right, because AppKit does not send
`validateMenuItem:` to an item that has one, so it could no longer be renamed
after the container it opens nor greyed out by the same rule as everything else
in that menu. It does not *disagree* with the chevron's menu — it is that menu's
first container entry, same title, same selector, same validation, same
container — it offers less. Both are built from `devContainerChoices` and go
through `newTerminalInContainer`, so they still cannot drift.

**The language servers choose the first, and are the one thing here still
choosing rather than asking.** A server starts because a file was opened, before
anybody has said anything, so there is no gesture to hang a question on. The
first in the menu's own sorted order rather than whichever container happens to
be up — that would make the toolchain the editor checks against depend on
whether somebody had opened a terminal yet, which is a coin toss with extra
steps. It is said out loud, once, in a notification naming the container it
picked. **This is a decision for whoever owns this, not one this closes**: a
setting naming the container a project's tools belong in, or the question asked
once when the project is opened, are both better answers than a rule. It is in
the open list below.

Proved by opening `devcontainers/two-containers` and taking the menu dump, then
opening a terminal in each: `IN:/workspaces/two-containers:abydos-devcontainer-22709-1`
and `IN:/workspaces/two-containers:abydos-devcontainer-22709-2`, two containers,
one project, both shells alive at once. A project with one devcontainer answers
exactly as it did.

0430 had to be fixed on the way, and it is not incidental: `relative()`
canonicalised the project and not the file, so under `/tmp` — where every
scratch project the harness makes lives — *both* files collapsed to
`devcontainer.json` and the two containers really were one. Both sides go
through `realpath` now.

`devcontainers/two-containers` in the examples repository is no longer described
as refused, and neither are the two `post-create` projects, which stopped being
refused earlier the same day; `check.sh` brings all three up.

## What is closed here, and what is not

All five of the steps above are done, which is what closes this entry. What it
raised and did not settle is still open, and none of it is waiting on anything
here — each is its own item when somebody wants it:

- **The CLI versus our own reader**, which the recommendation above left open
  and which nothing since has forced. The reader now covers the lifecycle
  commands too, so the subset is larger than it was and the boundary is still
  `features` and `dockerComposeFile`.
- **`features` and `dockerComposeFile`**, which are that boundary, refused by
  name, with an example each in the repository so the refusal can be watched.
- **Rebuilding.** Editing `devcontainer.json` still needs the app restarted, and
  `abydos-devcontainer:<project>` still accumulates. "Rebuild Container" is what
  people will look for.
- **The second half of ports** — choosing a different one when the host's is
  taken — and `forwardPorts` on Apple's runtime, refused by name.
- **`shutdownAction` and the battery question.** Nothing stops a container when
  a project closes; it lives until the app exits.
- **`overrideCommand: false`**, neither honoured nor refused.
- **Run configurations, the debugger and `make` inside the container.** The
  terminal and the language servers are in; those three are each their own piece
  of work, as the entry says.
- **A trust prompt** for a checkout nobody has vouched for, which is what
  `initializeCommand` really wants and what this settled deliberately without.
- **`hasDevContainer` ignores `subprojectRoot`**, so a devcontainer belonging to
  a subproject is invisible to the menu.
- ~~**`abydos-examples/devcontainers/check.sh` and its READMEs** still say the
  two `post-create` projects are refused.~~ Corrected, along with
  `two-containers`, and `check.sh` now brings all three up.
- **Which container a project's *language servers* belong in**, when it offers
  several. They take the first and say so; a setting, or the question asked once
  when the project is opened, is the real answer. See the section above.
- ~~**More than one `devcontainer.json` is refused.**~~ Lifted; the section above
  is what came of it. What is still true is that a project cannot say which of
  its containers is the *default* — there is no `.devcontainer` convention for
  it and sorted order is what stands in.

---

Its number is where it sits in the queue, not what it is worth doing next.
