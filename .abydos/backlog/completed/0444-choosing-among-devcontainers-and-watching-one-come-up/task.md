# 444. Choosing among several devcontainers, and watching one come up

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

## Steps

Written after the work rather than before it, which is the one rule this list
breaks and it is worth saying so plainly: this item was picked up as 0443 before
`## Steps` existed, and the checklist arrived with `AGENTS.md` on the merge that
renumbered it. Every line was ticked by looking at what is in the branch, not
from memory, and the three unticked lines are unticked because nobody did them.

- [x] Write down *which* devcontainer a project is worked in, beside the answer
      rather than inside it
- [x] Read a stored answer back, and turn one naming a container that has gone
      into a question rather than a failure
- [x] The question names the container it would use, and writes that name down
      with the yes
- [x] The pill's menu lists every container, marking the one in use
- [x] Choosing another moves the servers: stopped in the old, started in the new,
      both containers left running
- [x] Drop the attachment on a switch — otherwise the warm-up starts them back up
      in the container being left
- [x] The pill shows the `⬢` and not the name, and the name moves to the tool tip
      and the menu
- [x] Route the language-server start through `PreparingTerminal` so the build is
      visible
- [x] Decide whether that pane takes focus — it does not, ever
- [x] Decide what a failed build looks like — the pane is the error, the toast
      points at it
- [x] Decide what a start nobody watched leaves behind — nothing
- [x] Tests for everything the kit can reach: the identifier, the stale lookup,
      the second table, `detach`, and every new sentence
- [x] Drive the app at a project with four devcontainers and write down what was
      seen
- [x] Write down what was ruled out and what surprised us
- [x] `spec/devcontainers.md` says what the project now does
- [ ] Two projects with devcontainers open in two windows at once — reasoned
      about, never tried, which is the same gap 0438 left
- [ ] The tab a container leaves behind is restored as a shell on *this* machine
      with the `⬢` still in its name. Not new — it is what `newTerminalInContainer`
      has always written into `.abydos/session.json` — and not fixed here
- [ ] Decide whether a container whose build failed should be retried on the next
      open. It is, because the answer stays on file; nobody decided that

---

## What was built

### 1 and 2. The choice, and where it is made

**The question stays three answers**, which is the shape this entry proposed and
it holds for the reason it gave: the answers already stack rather than sit in a
row, so a fourth and a fifth would be a wall in the corner of the screen for a
decision most projects never have to make. It names the container it would use —
`containerChoice`, which is the one place that turns a yes into a *that one* —
and **which** is asked in the pill's menu.

**The answer is a second table rather than a fourth case.** `DevContainerConsent`
is unchanged: the three answers are still what somebody can say, and only one of
them is about a particular container. Folding a file path into the enum would
have given the other two a field with nothing to put in it, and would have made
every answer already written down unreadable by the app that wrote it. Kept
apart, `Settings.devContainerChoice` is a table beside the consent, and an answer
from 0433 or 0438 still reads as `container` and still means the project's
preferred one — which is what it did mean.

What is stored is **the file's path inside the project** —
`.devcontainer/go/devcontainer.json` — and not its path on this machine, since
the table is already keyed by the project; and not the container's `name`, which
is changed by editing the very file it is in. It is the same string for everybody
who checks the repository out, and it is readable in `defaults` by somebody
wondering what they said.

**A stale answer degrades into a question, and the degrading is one place.**
`consent(for:)` returns nil when the stored answer names a container the project
no longer offers, so everything downstream — the pill, the strip, the start —
sees a project nobody has been asked about, which is the truth. It is not the
nearest match: guessing is choosing a toolchain for somebody who chose a
different one. The verdict is cached per project so the file system is asked once
rather than on every lookup, and the log says why.

**Switching costs what the entry said it costs.** `move` takes a choice as well
as a consent, stops the project's servers, and starts them in the container that
was clicked. It costs one thing more than the other moves, and it was not
obvious: the attachment naming the old container has to go, or the warm-up that
follows finds it, decides the project already has a container, and starts the
servers straight back up in the one somebody has just asked to leave —
`DevContainerAttachments.detach`, which is deliberately not `letGo`. Moving onto
*this machine* keeps the attachment, because 0438 proved that coming back then
reuses the very same one with no second round of asking the image what it
carries.

**The toast that said "so the first is used" is gone** with the thing it was
apologising for, rather than being replaced by a quieter apology. The question
names the container, the answer is a *which*, and the menu lists them.

### 3. The pill

**The reason 0433 gave is answered rather than ignored, and this entry's answer
holds.** Naming the pill from `containerTabTitle` was about two things: one
source, so the pill and the tab in the same container could not drift; and that a
window scoped to one subproject of ten cannot say which container it means by
saying "container". The first is untouched — the name still comes from
`containerName`, and now so does the `⬢`, which is written once as
`containerMark` and worn by the tab, the menu item and the pill. The second is an
argument about the **menu item that opens one of several**, where the name is the
only thing telling two entries apart, and it is much weaker for a pill with
exactly one answer at a time in a window that already says which project and
which subproject it is showing.

So the pill is the `⬢` and the chevron, dimmed without the hexagon when the
container is there and not in use, exactly as 0438 left that distinction. The
name went to the two places with room: **the tool tip**, which now says something
in both states rather than only when declined, and **the menu**, whose state line
is likewise now in both states — a menu dropping out of a pill that says nothing
but `⬢` and then saying nothing itself would be the loss 0433 was guarding
against.

The menu's list of containers is where part 2 lands, and the words differ between
the two states because the gesture does. Nothing running: one **Use
&lt;container&gt;** per container, which is 0438's single way back grown to one
each. One running: the containers themselves, the one in use ticked, and clicking
another moves the servers there. A project with one container in use has no list
at all — a single ticked entry repeating the sentence above it is noise.

### 4. Watching one come up

**Routing, as the entry said, and two decisions.**
`MainWindowController.watchDevContainerStarting` finds the window showing the
project and hands `LanguageService` a `PreparingTerminal`; where there is no
window — `warmUp` runs while a project is still loading — it is the toasts that
were there before.

**Whether the pane takes focus: it does not, ever.** `takesFocus` is false on
this route, so even the shell the pane becomes leaves the editor where it was.
Read at 6, 12, 20, 30 and 40 seconds across several runs: `FOCUS … CodeView`
throughout, while a container was starting, while it became a shell, and while
one failed.

**What a failure looks like: the pane is the error and the toast points at it.**
The `postCreateCommand`'s own output stands above the refusal in red, the panel
is shown at once so it can be read, and the toast is one short sentence saying
where to look rather than an attempt to summarise a hundred lines of
`docker build`.

**A third decision the entry did not ask for, and it turned out to be the one
that mattered.** "The tab opens at once" is `PreparingTerminal`'s rule for
somebody who *asked* for a terminal, where an empty pane is a hang. Nobody asks
for this one. A warm start is `docker run` and an attach — a second or two — and
a tab left behind by every one of those is a shell nobody asked for, in a panel
whose tabs are written into `.abydos/session.json` and restored: one more every
session, watched accumulating to three before it was fixed. So the tab is made at
once, because there is no second chance at the output of a build, but it is **not
brought to the front and the panel is not opened**; if the start is still going
three seconds later the panel opens and the tab comes forward, and if it fails
that happens immediately. A start too quick to have been watched **takes its tab
with it** instead of becoming a shell. The warm case is therefore exactly as it
was before this item: no panel, no tab, nothing moved.

## What was seen, and what only tests cover

`~/dev/abydos-examples/devcontainers/python-language-server` for the ordinary
single-container shape, and a scratch copy of it with four devcontainers —
one carrying pyright, one plain, one with a twelve-second `postCreateCommand`,
one whose `postCreateCommand` fails — for everything else. Driven through the
app, with the scope asserted in every reading before anything was believed.

- **The question names the container it would use**, with its three answers, and
  the pill's menu beside it offers **Use &lt;each of them&gt;**.
- **The answer is written down as a which**: `devContainerConsent = { … =
  container; }` and `devContainerChoice = { … = ".devcontainer/plain-python/
  devcontainer.json"; }`, and the next run started that container with no
  question and named it in the pill.
- **Switching from the pill's menu**, both ways. Menu in use reads
  `Language servers are running in Plain Python… | — | ✓Plain Python… | Python,
  with its language server in the container | — | New Terminal | …`; pressing the
  unticked entry gives, in the log: `two-servers's language servers move to its
  devcontainer …` → `pyright-langserver was stopped by hand for two-servers` →
  `two-servers is worked on in Plain Python…` → `abydos-devcontainer-8342-2 is
  up; it has no language server(s)`. The old container's server is stopped before
  the new one is asked for, which is the whole of what 0427 exists for; the two
  containers stay up, and the shells in them with them.
- **The switch has a visible consequence**, which is why the second container is
  the one without a language server: the strip goes from silent to "Python has no
  language server in this project's devcontainer" and back.
- **A stale answer becomes a question.** With `.devcontainer/plain-python`
  renamed under it: the log says `two-servers was to be worked on in
  .devcontainer/plain-python/devcontainer.json, which it no longer offers; it
  will be asked again`, the question is in the corner, and the pill is dimmed.
- **The pill.** `PILL: shows=⬢ name=Python, with its language server in the
  container tip=Language servers are running in …` in use, and
  `shows=(icon only)` with the state sentence when not.
- **The slow start.** Switching to the deliberately slow container: at 8s a tab
  exists with `step 2 of 12` in it and the panel is **hidden**; at 12s the panel
  is open, the tab in front, `step 6 of 12`, and the keyboard still in the
  editor; at 20s the same pane is a shell in the container with all twelve steps
  above the prompt.
- **The failure.** The pane holds `installing the project`, `looking for the
  lockfile`, `ls: /nowhere/at/all: No such file or directory` and then the
  refusal in red; the toast beside it reads "Its language servers run on this
  machine instead. What the build said is in the One that cannot start tab in the
  terminal panel."
- **The warm start leaves nothing**, which is the decision that was not asked
  for: `PANEL: visible=false (no tabs)` at 4, 6, 8, 12 and 25 seconds through a
  container coming up, and `*tmux` alone in the example project.

**Three faults were found by driving it and none of them by reading it**: the
pill naming the container the project had just moved *off*, because it took the
first of the sessions that happen to be up and a switched project has two; the
shell nobody asked for accumulating one per session through the session file; and
"&lt;container&gt; is starting" outliving a start that had failed, which is
0438's sentence being asked a question it was not written for. All three are
fixed, and the last of them is a wart that predates this item and was only made
visible by giving failures a pane.

## Not proved, and left out

- **Nothing tests the window layer**, which is the same wall 0433 and 0438 hit:
  `LanguageService`, `MainWindowController` and `Toast` are in a target the suite
  cannot reach. What is unit-tested is what could be moved to where the tests are
  — the identifier and the stale lookup (`DevContainerFileTests`), the two
  tables and every new sentence (`DevContainerConsentTests`, now 24), and
  `detach` beside `letGo` (`DevContainerAttachmentTests`). Everything above under
  "what was seen" is covered by having been watched and by nothing else.
- **Two projects offering several containers, in two windows at once**, was
  reasoned about and not tried — the same gap 0438 left.
- **The three-second reveal is a judgement, not a measurement.** It was chosen so
  that a warm `docker run` never trips it and a build's first minute is visible
  almost at once; it was watched doing both, on one machine, with the image
  already there.
- **No rebuild on the pill**, still, and for 0433's reason: nothing in this app
  removes an image yet.
- **The tab a container leaves behind is restored as a shell on this machine**
  with the `⬢` still in its name, which is wrong and is not new — it is what
  `newTerminalInContainer` has always left in `.abydos/session.json`. This item
  made it matter less by not leaving one for a warm start, and did not fix it.
- **A container that fails is retried on the next open**, because the answer
  stays on file. That is probably right — a build fails for reasons that get
  fixed — but nobody decided it here.

2075 tests in 317 suites pass, `PlantUMLServerLiveTests` among them, in 73
seconds; it did not flake on the run that counts.

All four were seen working, so this one is done and moves to `completed`.

---

Previously numbered 0443. The backlog-spec branch had taken that number for
itself before this was written and was out of sight while it did, so both
existed for about an hour. The branch's keeps it: it was pushed, it is
in-progress, and its own commit message cites it. A number is given once, and
the way out of two items holding one is the way the README already describes —
the newer moves and says at the bottom what it was called.
