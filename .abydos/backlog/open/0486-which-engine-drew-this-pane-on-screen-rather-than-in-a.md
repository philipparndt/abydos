# 486. Which engine drew this pane, on screen rather than in a launch flag

> I runned it and activated libghostty - how do I see if it is active?

You cannot, and that is the whole item. 0485 made the setting real; nothing shows
which engine a pane is using. `--report-geometry` prints `engine=libghostty-vt`,
but that is a launch flag on a fresh process, not a question you can ask the app
you are sitting in.

**This is 0463 again, and the earlier report was almost word for word the same:**
*"the rust container is selected, but I have the strong feeling that it is not used
at all."* It was being used. The container runtime knew, the log knew and the
Running Servers window knew, and every one of those was somewhere somebody had to
go. The answer then was to put it beside the file. This is the same shape one layer
down.

## Why it matters more here than for the GPU renderer

Three facts are genuinely different and today they are indistinguishable:

- **The setting is on.** Settings says so.
- **This pane uses that engine.** `TerminalView.makeEngine` reads the setting when
  a pane is *built*, so a pane that existed before the setting changed keeps the
  engine it was made with. That is deliberate — "a running shell would throw all
  three away mid-session" — and it means the first thing somebody sees after
  turning it on is panes that have not changed.
- **That engine started.** If libghostty-vt will not initialise, `makeEngine`
  **falls back to ours** rather than handing back an engine whose every call is a
  no-op. Right behaviour, and silent.

So "I turned it on and I cannot tell" has three possible true answers, and the app
offers no way to choose between them. **And the whole point of the option is to run
it for weeks and report what differs** — which cannot work if a report cannot say
which engine drew the pane it is about.

## What already exists to build on

`TerminalView.engineNameForTesting` is exactly the right value and its comment
already says why: *"Read off the instance rather than off the setting, which is the
difference between reporting what is drawing and reporting what somebody asked
for."* It needs a way out to somebody's eyes.

## Worth deciding

- **Where.** The editor's footer took a chip for the language server (0463) and
  that is the closest precedent — but a terminal pane is not an editor tab and the
  panel's tab strip is already carrying a name, a running wash, a Claude badge and
  a close cross (0478). Somewhere in the pane's own furniture, the tab's tooltip,
  or Running Servers and Containers — which is where 0463 decided such questions
  belong — are all candidates. **The non-default engine is the one worth showing**;
  a mark on every pane in the normal case is a mark nobody reads, which is the
  argument 0463 settled by showing the container and not the local copy.
- **Whether the fallback says something louder.** A silent fall back to ours is
  right for *drawing*, and probably wrong for *telling*: somebody who asked for
  libghostty-vt and got our emulator because the library would not start should
  hear it once, not discover it in a launch flag.
- **What `unimplemented` looks like from the outside.** The engine already declares
  three honest gaps — OSC 440, `modifyOtherKeys`, and tmux's prompt row one line
  high. Somebody running the engine deliberately would want those where they can
  read them, rather than only in a source file. This item is where that belongs if
  anywhere.

## Steps

- [ ] Decide where it goes, favouring the non-default engine over a mark on
      everything
- [ ] A pane says which engine drew it, read off the instance and not the setting
- [ ] A pane made before the setting changed says the engine it actually has
- [ ] A fallback — the library missing or failing to start — is audible once
- [ ] The engine's declared gaps are readable by somebody who turned it on
- [ ] Watch it with the setting off, on, and in a pane that predates the change
- [ ] Write down here what was ruled out on the way
- [ ] `spec/terminal.md` says what the project now does
