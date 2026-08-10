# 443. Choosing among several devcontainers, and watching one come up

Four changes, reported from use. Two are gaps the code already knows about, one
reverses a decision that had a reason, and one is mostly wiring something that
already exists to somewhere it is not.

## 1. A project with several devcontainers can only activate the first

`LanguageService.ask(about:)` takes `DevContainerFile.choices(in: project).first`,
and a second place says so out loud rather than hiding it — the toast that
appears when there is more than one:

> This project offers N devcontainers and nothing says which one its tools belong
> in, so the first is used.

The comment above it records the decision and the reason it was deferred:

> What is still not offered is a *choice* of which, and that is deliberate rather
> than forgotten: a three-button question grows a button per container, and the
> answer that is written down would have to name a file rather than a yes. Left
> for whoever wants it.

So this is a handoff, not a bug report, and the two obstacles it names are the
real work:

- **The question cannot grow a button per container.** Three answers already
  stack rather than sit in a row because a devcontainer's name is a sentence.
  Five would be a wall. The likely shape is that the question stays three
  answers, and *which* container is chosen somewhere with room — the pill's menu
  from part 2 — with the question naming the one it would use and the pill able
  to change it afterwards.
- **`DevContainerConsent` records a yes, not a which.** Today `.container` means
  "use the devcontainer"; with several it has to mean "use *that* one", which is
  a stored file path rather than a case, and a path that may no longer exist when
  the project is opened next month. That needs a stale answer to degrade into a
  question rather than a failure.

## 2. Switching between them from the titlebar

The pill's menu already carries the state line, the way in or out, the terminal
and the file. The list of containers belongs there too — it is the one place
with room, it is where somebody is already looking when they think about the
container, and it makes part 1's answer reversible without reopening the project.

Switching is not free and the entry should not pretend it is: the servers in the
old container have to be stopped and started in the new one, which is 0438's
attachment work again from the other end. A switch that leaves the old
container's servers running is the fault 0427 exists for.

## 3. The pill is too wide — show that a container is active, not which

`containerTabTitle` gives the pill `"<name> ⬢"`, and a devcontainer's name is a
sentence: *"Python, with its language server in the container"*. In a titlebar
beside the project name, the branch and the subproject, that is most of the
window.

**This reverses a decision that had a reason, so the reason has to be answered
rather than ignored.** 0433 named the pill from `containerTabTitle` deliberately,
so the pill, the tab in the same container and the menu item that opens one could
not drift apart; and the naming argument was that *"a window scoped to one
subproject of ten that each have a devcontainer cannot say which one it means by
saying 'container'"*.

That argument is about the **menu item that opens one of several** — where the
name is the only thing distinguishing two items. It is much weaker for a pill
whose job is "this window is working inside a container", where there is exactly
one answer and the window already says which project it is. And part 2 gives the
name a home: the menu lists them, with the active one marked.

So: `⬢` alone, or `⬢` with something very short, and the name in the tool tip and
the menu. Keep the single source of the name — this is about what the pill
*shows*, not about it learning the name from somewhere else.

## 4. Activating a container should show the build, not a toast

The first activation can be minutes — an image pulled or a Dockerfile built, then
`onCreateCommand`, `updateContentCommand` and `postCreateCommand`. Today that is
progress toasts, which cannot show a build log and cannot show an error that
needs reading.

**`PreparingTerminal` already is this view**, and its own note describes exactly
what is being asked for: the tab opens at once, the work is written into it, and
then the same pane *becomes* the shell — one tab throughout, with the scrollback
keeping what happened. It is used when somebody opens a terminal in the
container, and not when the language-server path brings one up.

So the work is mostly routing: activation opens that pane and the build goes
there. Two things to decide rather than assume:

- **Whether the pane takes focus.** It must not steal the keyboard from somebody
  typing — the whole point of activating from a file is that they were doing
  something else. Showing the panel without moving focus is probably right, and
  0440 is deciding the same question from the other direction.
- **What happens when it fails.** A failed build currently produces a toast and a
  strip. With a log pane, the pane is the error, and the toast becomes a pointer
  to it rather than an attempt to summarise a hundred lines of `docker build`.

## Order

Parts 1 and 2 are one piece of work — the choice needs somewhere to be made. Part
3 is small and independent. Part 4 is independent of all of them and is the one
somebody feels first, since it is the difference between minutes of silence and
minutes of visible progress.
