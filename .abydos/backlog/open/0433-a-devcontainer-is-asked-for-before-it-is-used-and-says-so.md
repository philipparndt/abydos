# 433. A devcontainer is asked for before it is used, and says so in the titlebar

Opening a `.py` file in a project with a `devcontainer.json` currently starts a
`docker build` without asking anybody. That is the right *default behaviour*
and the wrong *default manners*: the first one can be several minutes and a
gigabyte of disk, on a machine that may be on a train, and nothing was said
before it began.

The second half is worse, because it outlasts the first. Once the container is
up there is nothing on screen that says this project is being worked on inside
one. What exists today is transient or indirect: the strip above the file says
"Python's language server is starting in this project's devcontainer" and then
*withdraws itself* the moment the server lands, which is exactly when somebody
would want to know; the `DevContainers.Progress` toasts pass; and the only
lasting sign is a terminal tab called `<name> ⬢`, which is in the panel, not on
the window, and only exists if a terminal was opened.

**This was reported from use, and the report is the evidence.** Opening
`abydos-examples` with `devcontainers/python-language-server` as its subproject:
"I do not understand how the devcontainer feature should work. How do I activate
a devcontainer and how do I see that it is activated for the current project?
Opening a terminal does not feel intuitive and seems to also not do the job."
Every part of that is a fair reading of what is on screen. There is no activate
gesture because activation is automatic; the terminal is a shell in the
container rather than the switch that turns it on; and the state is invisible.
A feature whose whole design is "it just happens" has to say that it happened.

## What to build

**Ask, once, per project.** The first time a project's devcontainer would come
up, ask whether to use it — naming the container, and saying that the first
start is a build. `LanguageService.startDevContainer` is the one choke point:
every route in, from any language and any number of files at once, is already
funnelled through it and guarded by `devcontainerStarting`, so the question has
one place to live and cannot be asked twice for one container.

**Remember the answer where it belongs, which is not the project.** The
`devcontainer.json` is committed and shared with everybody who checks the
repository out; whether *this* person wants a container is theirs, and putting
it in `.abydos/` would push one developer's answer onto the team. It goes in the
app's own settings, keyed by the project path, the way other per-machine
preferences are.

**Show it in the titlebar, beside the subproject.** `SubprojectPillButton` is
the model, in the same place and the same shape: a pill saying the
devcontainer's own `name` with the `⬢` the tab already uses.
`MainWindowController` has everything it needs — `devContainerRoot`,
`devContainerChoices` and `containerTabTitle(for:in:)` — and `layoutTitlebarPills`
already arranges two pills, so this is a third rather than a new mechanism. The
pill is the place to hang the rest of the gestures: turn it off, rebuild it,
open the `devcontainer.json`.

The pill says *running*, not *configured*. A project with a `devcontainer.json`
that nobody has said yes to has no pill; that is the difference between the
menu item's `hasDevContainer`, which is about the file, and this, which is
about a container that exists.

## The one that needs deciding

**What "no" means.** Declining has to leave the project in a state, and the two
candidates disagree with something already written down. The devcontainer path
deliberately refuses to fall back to a server on this machine — the comment at
`serverInDevContainer` says why, and it is a good reason: the same code getting
different answers depending on whose laptop it is on is the fault the whole path
exists to prevent. But somebody who says "not now" on a train wants the host's
servers, not silence.

The likely answer is that declining is explicit rather than implied: "work on
this machine instead" is a different sentence from "not now", and the strip
should then say which of the two is in force, since a Python file with no
squiggles has to be distinguishable from one being checked by a server that is
not the project's. Neither reading should be picked quietly — this is the one
place where the item's manners and the item's correctness pull apart.

## Ruled out

**The terminal as the switch.** It is what was reached for, and it is not it:
`newTerminalInContainer` opens a shell in the container and has nothing to do
with which machine the language servers run on. Making it the activation would
make a shell a side effect of a preference, and leave somebody who never opens a
terminal with no way to say yes.

**A modal at project open.** The question belongs at the moment something needs
the container, not at the moment the window appears, because most sessions in a
project never open a file the servers care about, and a dialog in front of a
project that is only being read is the kind of prompt people learn to dismiss
without reading.
