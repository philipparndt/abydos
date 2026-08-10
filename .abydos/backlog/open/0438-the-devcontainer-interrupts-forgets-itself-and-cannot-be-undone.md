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
