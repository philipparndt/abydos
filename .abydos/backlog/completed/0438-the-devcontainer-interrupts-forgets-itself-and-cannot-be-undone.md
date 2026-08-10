# 438. The devcontainer question interrupts, forgets itself, and cannot be undone

Three faults, all reported from using what 0433 built. The first is a rule this
repository already wrote down and then broke; the second is a bug with an exact
cause; the third is a gap.

## 1. The question is a modal, and it should be a toast that waits

`Toast.swift` opens with the rule:

> The rule this exists to enforce: nothing interrupts unless the user asked a
> question. Confirmations before something destructive are still modal, because
> those *are* the answer to something they just did.

Opening a `.py` file is not a destructive gesture and it is not a question. The
container ask appears on its own, takes the keyboard and stops everything —
which is precisely what that comment forbids. 0433 reached for `NSAlert`
(`LanguageService.swift:990`, sheet when there is a window and `runModal` when
there is not) and the rule should have caught it.

It becomes a toast, titled **"Activate dev container"**, and it **stays until it
is answered** — accepted or declined. That last part is why this is not a
one-line change: `Toast` today has a single `action` and `actionTitle`, and
`ToastPresenter.lifetime` is a fixed 8 seconds with no way to say otherwise. So
the type needs two genuinely new things:

- **No expiry**, for a toast that is a question rather than news.
- **Several answers**, since there are three: use the container, work on this
  machine, not now.

Both have consequences to decide rather than discover: what a non-expiring toast
does to `ToastPresenter.maximumVisible` (4, newest at the bottom) when it cannot
be pushed off; and what happens to a question still on screen when the project it
is about is closed underneath it.

## 2. Switching project loses the container — and here is exactly why

Reported as "the devcontainer gets lost when switching back", and it is not the
session that is lost.

`stop(for:)` keeps `devcontainerSessions` on purpose, and the comment says why —
0424's reason, that switching away and back has to be instant and there is
somebody's terminal in it. But on the same path it removes:

    devcontainerCommands.removeValue(forKey: path)

and `serverInDevContainer` gates every start on precisely that map:

    guard devcontainerCommands[path]?.contains(resolved.definition.command) == true else {
        … "\(command) is not in this project's devcontainer." …
    }

`devcontainerCommands` is filled once, by `startDevContainer`, when a container
comes up. Come back to the project and the session *is* found — so the start
path is skipped, so nothing refills the map — and the guard then fails. The
language is reported as having no server in the container, with a sentence that
is false and a hint telling somebody to edit a Dockerfile that is already
correct.

**The session and the list of what it provides are one fact.** They have to be
kept together or dropped together. Keeping the session and dropping its
capabilities is the one combination that produces a confident wrong answer.

Worth checking while in there: `devcontainerFiles` and `devcontainerProjects`
are dropped on the same path, and whether either has the same relationship to a
kept session.

## 3. Declining hides the only way back

`refreshDevContainerPill` sets the pill to nil when consent is `.thisMachine` or
`.notNow` — and the pill's menu is where 0433 put "the way out of it". So the
gesture that most needs undoing is the one that removes its own undo.

The strip does carry a button, which is why 0433 recorded that neither decline is
irreversible. But the strip only appears over a file whose server is missing, so
somebody who declines and then works on something else has no way back and
nothing on screen saying which state they are in. From the window it reads as
gone for good — which is how it was reported.

A project that *has* a `devcontainer.json` and is not using it is a state worth
showing, quietly: the pill stays, saying it is not in use, and its menu offers
the way in. `hasDevContainer` already distinguishes "there is a file" from
"there is a container running", so the distinction exists — the pill just does
not use it.

## Worth deciding, not guessing

- **What the declined pill says and how loud it is.** It must not nag: somebody
  who chose to work on this machine chose it. A dimmed pill saying the container
  is available is probably right; a warning colour is certainly not.
- **Whether "not now" comes back.** It is deliberately not stored, so it means
  "this afternoon". Whether the toast reappears on the next file opened, or stays
  quiet until the project is reopened, is a real choice — the first is a nag and
  the second may be a state somebody cannot get out of without the pill from 3.
  These two answers depend on each other and should be settled together.

---

## What was built

### 1. The question is a toast that waits

`Toast` grew the two things the item said it needed, and they are general
because it is shared infrastructure: **`Lifetime.untilAnswered`** beside the
fixed eight seconds, and **`Toast.Answer`** — a title and a closure — instead of
one `action`. The devcontainer question is one caller; nothing else uses either
yet.

The answers are stacked rather than in a row. A devcontainer's `name` is a whole
sentence — the example project calls its own "Python, with its language server in
the container" — so three of them side by side would be three truncations, and
down the side they read as a list of things somebody could say. A question has no
close cross and ignores clicks on its body: the only ways out are its answers,
which is why there are three rather than two.

The title is fixed at **"Activate dev container"** and the sentence underneath
names the project, the container and what the first start costs, cut down from
`explanation` to a width a corner 340 points wide actually has.

**What a non-expiring toast does to `maximumVisible`.** Nothing pushes a question
off. The cap of four now counts only the toasts that can be pushed off, so a
corner full of questions may be taller than four rather than quietly shorter by
one decision made for somebody by how much else happened to be going on. In
practice there is at most one at a time, because whatever asks holds a guard
across the asking.

**What happens to a question when the project closes underneath it.** It is
withdrawn — `Toast.withdraw` by identifier, and the window does it whenever it
stops showing the scope the question names, which is switching project or moving
between subprojects. **Withdrawing is not answering.** Nothing is decided and
nothing is written down: `onWithdrawn` gives `devcontainerStarting` back, so the
next file opened in that project asks again. Leaving it there instead would put
an answer about a project nobody is looking at one click from being given, over a
window showing a different one.

**A fault found by running it, not by reading.** A toast goes to whichever window
speaks for the app, and while the app is starting up that is none of them: no key
window, no main window, nothing visible yet. `warmUp` runs inside exactly that
gap, so on one run the question went nowhere at all — and the project went on
holding the guard that stops it being asked twice, so it could never ask again
and the strip said "starting in this project's devcontainer" for ever. It is the
same gap 0433's modal needed its wait-for-a-window loop for. `Toast.ask` waits it
out a quarter of a second at a time and, after ten seconds, withdraws rather than
forgets. Silence is the one outcome that must not be reachable.

### 2. The container, and two faults rather than one

**The one the item names.** `DevContainerAttachment` is the session and the list
of what it carries as one value; `DevContainerAttachments` is the table of them,
and `letGo` is the one place that says what a project being let go of keeps. It
keeps the container and its capabilities — the container is deliberately left
running — and drops only the languages that were waiting for one, since nothing
is going to start them now. The combination that produced a confident wrong
answer is no longer spellable.

`DevContainerAttachmentTests.switchingAwayAndBackKeepsWhatTheContainerCarries`
was watched failing against the old behaviour, at the assertion about switching
back, before it was made to pass.

The two the item asked about are both fine as they were. `devcontainerFiles` is a
fact about the disk and re-reading it cannot contradict a kept session — a
session exists only because there was a file, and if the file has since gone the
fresh read is the more correct answer. `devcontainerProjects` is re-derived and
then immediately overwritten by whichever answer applies.

One hole closed on the way past: a devcontainer stopped by hand from the list of
running tools goes through `DevContainers` and never through `LanguageService`,
so the attachment used to outlive the container it named. It now goes when the
container does.

**And the one that was actually being reported.** Driving the app found that
switching away and back never reached `stop(for:)` at all. `load` read the
session file at the *bottom*, after `selectedConfigurationName = nil` had fired
its `didSet` and called `rememberOpenEditors` for a window whose project was
already the new one and whose `subprojectRoot` had been cleared three lines up —
so the file was rewritten without its `subproject` a few microseconds before the
line that needed it looked. The window came back scoped to the whole repository:
no subproject, so no `devcontainer.json`, so no pill and no container. Reading
the session first is the whole fix, and `switchProject` already had the rule
written above its own read.

The item's diagnosis was right about a real fault and it is not the one the
report came from. Both are fixed.

### 3. The pill has two states

It is now about the `devcontainer.json`, which is what `hasDevContainer` has
always been about. Lit with the `⬢` the terminal tab wears: this project's tools
are in that container. Dimmed without it: there is one and they are not. It never
claims a container is in use when it is not, which was the whole of 0433's rule;
what has changed is that "there is one and it is not in use" now has somewhere to
be said.

The menu follows. Not in use: what state it is in, then **Use &lt;container&gt;**,
then the terminal and the file. In use: as before, ending in "Work on This
Machine Instead" — which is not offered to a project already on this machine,
since that is a switch with nothing on the other side of it.

## The two that were left open, and depend on each other

**What the declined pill says.** The pill itself says nothing but the container's
name, dimmed to the same grey the tree gives an ignored file. Not a warning
colour, not a badge, no extra words: somebody who chose to work on this machine
chose it, and anything louder is the app arguing with them. The `⬢` is dropped
because it is the mark of being *inside* a container. The sentence is in the tool
tip and at the top of the menu, for whoever goes looking, and it states a fact
about the container rather than a recommendation. "Nobody has been asked" reads
the same as "not now" on purpose — they are the same state of the world, and
telling them apart would be reporting the app's bookkeeping rather than the
project.

**Whether "not now" comes back.** It does not. It stays quiet until the project
is reopened, and it is still not written down, so reopening asks. That answer is
only available *because* of the first one: before the dimmed pill existed it
would have been a state nothing on screen could get somebody out of, and with the
pill there permanently, asking again on the next file opened would be a nag with
a visible alternative sitting beside it. The two really do decide each other, and
this is the pair that holds: **a standing, quiet way in, and no second ask.**

## What was seen on screen

Against `abydos-examples` with `devcontainers/python-language-server` as its
subproject — the shape all three were reported against — through the app, with
the image already built. 0433's `--lsp-banner report` was not trusted: it fires
once at a fixed three seconds, and a container coming up, a server indexing and a
project just switched back to are all still settling then. Every reading below is
one of several taken across a run.

- **The question stays.** Read at 4, 8 and 14 seconds: still there, with its
  three answers, while two pieces of news beside it appeared and expired. The
  eight-second lifetime is what took those away and it does not apply to this.
- **Answering it.** "Use Python, with its language server in the container" →
  the container comes up, the strip goes from "starting in this project's
  devcontainer" to nothing at all, and the pill lights with the `⬢`.
- **"Not Now"**, which 0433 could not exercise at all. The toast goes and does
  not come back — read again at 22 and 32 seconds — the strip says "Python's
  language server is in *&lt;container&gt;*, which has not been started" with the
  offer beside it, and the dimmed pill stays with the way in in its menu. **This
  is the first time either of 0433's declined sentences has been seen on screen
  rather than in a unit test.**
- **"Work on This Machine Instead"** from the pill's menu: the pill dims and its
  tool tip reads "Language servers are running on this machine, not in
  *&lt;container&gt;*". The strip says "install pyright-langserver", which is
  0433's rule and not a fault — that sentence is the useful one until a server
  here is actually answering.
- **The way back**, twice. From a `notNow` project with nothing running, and from
  a `thisMachine` project **with the container still up** — which is the exact
  path the item's second fault lived on, since it goes through `stop(for:)` with
  a live session. The log reads `python-language-server's language servers move
  to its devcontainer` and then `pyright-langserver started … container exec
  abydos-devcontainer-10641-1`, the *same* container, with no second `is up; it
  has` line: the kept attachment supplied both halves. Before, this is where
  "pyright-langserver is not in this project's devcontainer" was written.
- **Switching away and back.** Pill and scope read at 30, 47, 60 and 75 seconds
  across a switch to another project and back: `python-language-server` →
  `abydos` → `python-language-server`, pill lit again, strip silent, and the log
  shows pyright re-announced the file to the server already running in the
  container rather than a new one.
- **The question withdrawn and asked again.** Question on screen at 8s, switch
  project at 12s, corner empty at 16s, switch back at 20s, question on screen
  again at 26s and still at 36s.

## Not proved, and left out

- **No test covers the window layer.** `LanguageService`, `MainWindowController`
  and `Toast` are in a target the suite cannot reach, which is the same wall
  0433's tests hit. What is unit-tested is what could be moved to where the tests
  are: the attachment and its lifecycle (`DevContainerAttachmentTests`, five
  tests) and every sentence the question and the pill are made of
  (`DevContainerConsentTests`, now eighteen). The pill's dimming, the toast's
  layout and the withdrawal on switching project are covered by having been
  looked at, and by the harness readings above, and by nothing else.
- **One question at a time is assumed rather than enforced.** Two projects, each
  with a devcontainer, opened in two windows at once would put two questions in
  one corner, and the eviction rule deliberately lets the stack grow rather than
  drop one. That was reasoned about and not tried.
- **Which of several containers** is still not asked, exactly as 0433 left it.
- **The dimmed pill for a project nobody has been asked about yet** reverses one
  line of 0433 — "a project with a devcontainer.json that nobody has said yes to
  has no pill". That rule was written when the pill had one state; it has two
  now, and the dimmed one says the opposite of what 0433 was guarding against.
- **A `--lsp-banner`-style single reading is still there** and still misleading.
  It was left alone and `--banner-at` added beside it rather than changing what
  existing scripts get.

1982 tests in 306 suites pass, `PlantUMLServerLiveTests` among them on the run
that counts.

All three were seen working, so this one is done and moves to `completed`.
