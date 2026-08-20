## Why

> I runned it and activated libghostty - how do I see if it is active?

You cannot, and that is the whole item. 0485 made the setting real; nothing shows
which engine a pane is using. `--report-geometry` prints
`engine=libghostty-vt`, but that is a launch flag on a fresh process, not a
question you can ask the app you are sitting in.

**And the point of the option is to run it for weeks and report what differs**,
which cannot work if a report cannot say which engine drew the pane it is about.

## What Changes

- **A pane says which engine drew it**, read off the instance rather than off the
  setting. `TerminalView.engineNameForTesting` is already exactly that value and
  its comment already says why — *"the difference between reporting what is
  drawing and reporting what somebody asked for"*. What it needs is a way out to
  somebody's eyes.
- **Three facts that are true separately stop being indistinguishable.** Today
  "I turned it on and I cannot tell" has three possible true answers:
  - the setting is on, which Settings says;
  - *this pane* uses that engine — `makeEngine` reads the setting when a pane is
    **built**, so a pane older than the change keeps the engine it was made with,
    which is deliberate and means the first thing somebody sees after turning it
    on is panes that have not changed;
  - that engine **started** — if libghostty-vt will not initialise, `makeEngine`
    falls back to ours rather than handing back an engine whose every call is a
    no-op. Right behaviour, and silent.
- **The fallback is audible once.** Silent is right for *drawing* and wrong for
  *telling*: somebody who asked for libghostty-vt and got our emulator because
  the library would not start should hear it, not discover it in a launch flag.
- **The non-default engine is what is shown**, not a mark on every pane. This is
  0463's settled argument — it showed the container and not the local copy —
  and a mark in the normal case is a mark nobody reads.
- **Not proposed: changing when a pane picks its engine.** A running shell would
  throw its scrollback away mid-session, which is why it is decided at build.

## Capabilities

### New Capabilities

<!-- None. -->

### Modified Capabilities

- `terminal`: the capability already says a pane can be emulated by libghostty-vt
  instead of by our own emulator, and that an engine says what it cannot do. What
  it does not say is that a pane can be asked which of them drew it.

## Impact

- `Sources/AbydosApp/Terminal/TerminalView.swift` — `engineNameForTesting`, and
  wherever the answer is shown.
- The panel's tab strip, the pane's own furniture, or Running Servers and
  Containers — 0463 decided such questions belong in the last of those, and the
  strip is already carrying a name, a running wash, a Claude badge and a close
  cross.
- `.abydos/backlog/spec/terminal.md`.
- From `.abydos/backlog` item 0486, which is 0463 one layer down.
