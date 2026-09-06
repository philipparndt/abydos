## Context

What runs when a project opens, today: `RunConfigurationDiscovery` reads
`Makefile`, `launch.json`, `Package.swift`, `pom.xml`, gradle files and
devcontainer definitions and is ready to launch what they name; `LanguageServers`
locates a command — from the machine, and from the project's own tree — and
starts it; the terminal opens a shell in the project's directory; a devcontainer
is a container the project's file describes; a commit runs `.git/hooks`.

Environment is assembled in several places for several tools:
`RunConfiguration` expands a launch.json `env` block, `MakeLaunch` and
`ArgumentLine` build one for a launch, `Sops` runs with the app's environment,
`GitRepository.run` takes an `environment:` parameter. Each is a place a
project-supplied variable could reach a subprocess.

The persistence precedent is `RecentProjects`: a JSON file in
`~/Library/Application Support/Abydos/`, loaded at init, and — the part that
matters here — **not written at all in a driven run**, because a capture run
putting a temporary directory into somebody's real list is that list being
wrong.

## Goals / Non-Goals

**Goals:**

- Nothing from an untrusted project is executed, and nothing it names reaches a
  subprocess as environment.
- Reading a project is unaffected: tree, editor, search, git history, diffs,
  blame, previews.
- Trust is asked for once per folder, answerable for a parent folder, and
  withdrawable.
- One gate, asked in one place per execution path, so that the next way to run
  something has to go past it.

**Non-Goals:**

- Not a sandbox: once trusted, a project's build does what builds do.
- Not a scanner or a heuristic about which projects "look" dangerous.
- Not a per-file or per-command trust: the unit is the folder, which is the
  unit somebody actually reasons about.
- Not trusting by signature, checksum or lock file — see below.

## Decisions

### How trust is remembered: a list of folders, in the app's own support directory

`~/Library/Application Support/Abydos/trust.json`, beside `recents.json` and
with the same shape and the same driven-run rule. Each entry: the folder's
**resolved** path (symlinks and `/tmp` settled, the way `SopsRules` and
`GitRepository` already standardise), when it was trusted, and which gesture
did it — this folder, or everything under it.

**Never inside the project.** A `.abydos/trusted` file would let a downloaded
repository grant itself the trust this whole change exists to withhold, and no
amount of signing fixes what a `git clone` can write.

**A parent can be trusted.** One entry for `~/dev` covers every checkout under
it, which is the difference between a feature people use and a dialog people
learn to dismiss. A parent entry is matched by path prefix on the resolved
path, at a component boundary — `~/dev` trusts `~/dev/abydos` and not
`~/development`.

*Ruled out:* remembering a fingerprint of the project's contents. Trust would
then expire on every `git pull`, and a question asked after every pull is
answered without being read — which is worse than not asking. VS Code learnt
this and stores the folder.

*Ruled out:* the folder's file id (inode) beside the path, to notice a
directory deleted and replaced. It catches a real case, and it also fires on a
restore from backup, a move, and a checkout recreated by a tool — a re-ask
somebody cannot explain is a re-ask they click through. It is worth revisiting
if the replaced-folder case is ever seen in practice; the store's shape leaves
room for the field.

### What "untrusted" gates, and where the gate is

One function — `ProjectTrust.isTrusted(root)` — asked at the point of
execution rather than at the point of display, because a menu that hides its
items teaches nothing and a menu that explains itself teaches once. Run,
debug, build, test, Make goal, gradle and maven wrappers, devcontainers,
language servers, formatters, schemes, agent commands and the terminal each
ask it, and each says the same sentence when the answer is no, with the button
that changes it.

The gate returns a decision rather than a Bool where the caller can do
something useful with the reason, so "not trusted" and "trusted" are not the
only two answers a call site has to handle blindly.

### Environment: the project's variables are dropped, not filtered

An allow-list of "safe" variables is a list somebody has to keep correct
forever, and the interesting ones are not obviously dangerous by name —
`SOPS_AGE_KEY_CMD` reads like configuration. So while a project is untrusted,
**no variable the project supplies is applied to any process**: not a
launch.json `env`, not a devcontainer's `containerEnv`, not an `.envrc`, not a
run configuration's own. The app's own environment — the `PATH` it needs, the
variables it sets for git's prompts — is unaffected, being this app's and not
the project's.

*Amended on 2026-09-06, after the first cut refused a terminal outright.* The
argument for refusing was that a shell in the project's directory sources
whatever the machine's shell configuration sources and that direnv runs an
`.envrc`. Neither survives contact: the shell and its configuration are the
person's own, typing `make` in it is them choosing to run the project's code
exactly as they would in Terminal.app, and direnv refuses an `.envrc` it has
not been allowed. What refusing *did* cost was the way somebody moves between
projects in a terminal-first editor — reported as exactly that.

So the terminal opens, and the one project-driven thing in it is switched off:
`DIRENV_DISABLE` for an untrusted project, belt to direnv's own brace and
best-effort by nature. The rule this leaves is the sharper one: **this
application starts nothing of the project's by itself**, and does not pretend
to police what somebody types.

### Git hooks: `--no-verify`, and said out loud

A commit is a git write that runs `.git/hooks/pre-commit` — code the project
carries, and code a clone brings with it. In an untrusted project the app
commits with `--no-verify` and says so where the commit is made, rather than
refusing the commit (which would make an untrusted project read-only for work
somebody is legitimately doing) or running the hook quietly (which is the hole).

*Ruled out:* refusing git writes entirely. Reading a repository and committing
a note to it is not the risk this change is about, and a mode that cannot
commit is a mode people leave.

### What the window says

A strip at the top of the window: what is held back, in a sentence, and
**Trust This Project**. Trusting is a sheet naming the folder, offering the
parent folder as the wider choice, and saying what trusting turns on. The
settings page is where trust is listed and taken back.

*Ruled out:* a modal at open. A window that cannot be looked at until a
security question is answered is a security question answered by reflex.

*Amended on 2026-09-06, from two reports about the strip itself.* **What is
held back** was a toast, and a toast goes on a timer: it is a list somebody
reads while deciding, so it is a popover from the button that asked, and it
says what still works beside what does not. And the strip can be **dismissed
without trusting anything** — a strip whose only exit is trusting the project
is a strip that gets projects trusted — which moves the trust gesture into the
File menu as well, since a window with no strip still needs one.

## Risks / Trade-offs

- [A gate missed on some path] → the tasks add the gate at the point of
  execution and the proof drives each path in an untrusted project; a new way
  to run something is added beside an existing one, which is where the gate is.
- [Trust by path is trust in a name] → said in the settings page in those
  words, and the parent-folder entry is offered rather than assumed.
- [People trust everything to make the strip go away] → the strip is a strip
  and not a modal, the untrusted window is fully usable for reading, and the
  sheet says what trusting turns on.
- [`--no-verify` surprises somebody whose hooks format their code] → it is
  said on the commit itself, not only in a settings page.
- [A driven run writing somebody's trust list] → the store follows
  `RecentProjects`: in a driven run it is kept in memory and never written.

## Open Questions

None that block a first cut. The replaced-folder case — a trusted path whose
directory is deleted and recreated by something else — is knowingly left to the
path check, with the store's shape leaving room for a file id if it is ever
seen.
