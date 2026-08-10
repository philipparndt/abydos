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

---

## What was built

### The question, at the one place it can be asked once

`LanguageService.startDevContainer` was right about being the choke point, and
the guard was already there: `devcontainerStarting` is now held across the
*asking* as well as the starting, which is what makes ten files opened at once
one question rather than ten. The function became three — ask, apply, bring up —
so that an answer given a minute later walks into the same code path an answer
already on file walks into.

Three buttons, because the item's open question resolves that way. **"Use
&lt;container&gt;"**, **"Work on This Machine"**, **"Not Now"**, Escape on the
last. The paragraph under the question says where the image comes from and what
the first start costs, in minutes and disk, read from the file rather than
guessed at: `DevContainerConsent.FirstStart.of` looks at `image` against
`build.dockerfile` and names the Dockerfile the way the project names it.

### What "no" means, which was the one that needed deciding

The two declines are different sentences and both are kept as such.

- **Work on this machine** — the servers run here, deliberately, and the project
  knows it. This does not contradict `serverInDevContainer`'s refusal to fall
  back: that comment is about the app *quietly* choosing a toolchain, and this is
  somebody choosing one by name. Nothing quiet about it.
- **Not now** — nothing starts, in the container or on this machine. It is the
  only one of the three that is **not written down**: it is an answer about this
  afternoon, and a preferences file that remembered it would turn the train and
  the battery into a decision nobody made. It is held until the project is let go
  of, and `shutdown(project:)` forgets it.

The strip says which is in force. That cost one reordering in `notice`: the
`suits` guard moved above the running-server return, because a project worked on
here rather than in its container is **the one case where a running server has
something to say about itself** — and "a Python file with no squiggles" and "one
being checked by a server that is not the project's" are otherwise the same
picture. The two orders agree everywhere else, since a server that is running is
one that suited the project when it started. Shown at different moments on
purpose: "not now" always, because silence has to say why it is silent; "work on
this machine" only once a server here is actually answering, because before that
"install pyright" is the useful sentence and a note about a container somebody
has already turned down would be the app arguing with them.

The strip grew one button — `ServerNotice.Offer`, one case — so that neither
decline is a decision nothing on screen can reverse. Taking it shuts the project
down first, because two sets of servers answering about one file is one of them
publishing diagnostics from a toolchain that is no longer the project's; the
editor re-opens what it holds through the same `rescope` a subproject change
already uses, driven by a new `ideaiLanguageServersMoved`.

### Where the answer lives

`Settings.devContainerConsent`, a table keyed by the **canonical** project path.
Canonical because `/var` is a symlink and every scratch project the suite makes
lives under it, which is 0430's fault one table along; a test holds both
spellings of one directory against it. Not in `.abydos/`, for the reason the item
gives.

### The pill

`DevContainerPillButton` beside the subproject, with
`MainWindowController.containerTabTitle` producing the whole label, so the pill
and the tab in the same container cannot come to disagree. A chevron rather than
the subproject pill's cross: that cross gives the whole project back and costs
nothing, and everything this offers changes which toolchain the code is checked
against.

It shows when a container for this project is **up and not declined** — a
project whose servers were put on this machine has no pill even while somebody's
shell is still in the container, because the pill reads as "this project's tools
are in there". `DevContainers` grew a notification for it, since nothing could
ask: a container comes up because a file was opened in a window that was never
consulted.

Its menu is New Terminal, Open `.devcontainer/devcontainer.json`, and Work on
This Machine Instead. The terminal entry does **not** repeat the container's
name the way the View menu's and the panel chevron's do — those are read a long
way from anything saying which container is meant, and this one drops out of a
pill with the name written on it.

## What was proved, and how

Against `abydos-examples/devcontainers/python-language-server` with the image
already built, through the app rather than through the kit:

- **The question is asked and the container does not start behind it.** With
  nothing on file the run reaches the sheet and stops there — no `is worked on in
  a devcontainer`, no container, no pill. That is the whole complaint fixed.
- **The answer is kept, per project, by canonical path.** After answering,
  `defaults read` showed
  `devContainerConsent = { "…/devcontainers/python-language-server" = container; }`
  and the next run started the container with no question.
- **The pill.** With `container` on file: `PILL: Python, with its language server
  in the container ⬢`, refreshed by the notification at the moment the container
  came up (`running=1`), not by a timer.
- **Declining.** With `thisMachine` on file: no container, no pill, and the log
  reads `python-language-server's devcontainer is not available (its language
  servers were asked to run on this machine); its language servers run on this
  machine` followed by the host looking for `pyright-langserver`.

**A fault found by running it.** An instrumented run printed `key=false
main=false windows=2 active=false` at the moment the question is first put:
`warmUp` runs while the project is loading and neither window is key or on
screen, so reaching for `runModal` there puts an app-modal dialog in front of
nothing at all — worse manners than the silence this item is about. It now waits
a quarter of a second at a time, twenty times, for a window to hang a sheet on.

## Not proved, and left out

- **The two declined sentences were never seen on screen.** The harness's
  `--lsp-banner report` fires at a fixed three seconds and said `no banner` for
  the declined project — but it also says `no banner` for a plain Python file
  with no pyright installed in a project that has no devcontainer at all, so the
  report is not measuring what was wanted here rather than the strip being wrong.
  The sentences are covered by unit tests instead. Somebody with the app in front
  of them should look at the strip once.
- **"Not now" was never exercised in the app**, because it cannot be answered
  from the harness and is deliberately not settable through the preferences.
- **Which of several containers** is still not asked — the question names the
  first, as before, and the toast still says so. A three-button question grows a
  button per container, and the answer written down would have to name a file
  rather than a yes.
- **No rebuild on the pill.** Nothing in this app removes an image yet, and a
  "Rebuild" that only restarted the container would look like it did the
  expensive thing and would not have.
- **No settings page.** The table is readable in `defaults` and every project's
  answer is reachable from the project itself; a list of paths in the preferences
  window would be a second place to keep them in step.

`DevContainerConsentTests` is fourteen tests over the storage and every sentence.
The suite is 1905 tests. `PlantUMLServerLiveTests` flakes under the load of the
whole suite — twice in five runs — and it does so on the commit this branch
started from as well, which was checked rather than assumed.

---

Its number is where it sits in the queue, not what it is worth doing next.
