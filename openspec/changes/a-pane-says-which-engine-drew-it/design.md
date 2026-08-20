## Context

`TerminalView.makeEngine` reads the setting when a pane is **built** and falls
back to our own emulator when libghostty-vt will not initialise. Both are
deliberate: a running shell would lose its scrollback if the engine changed
under it, and an engine whose every call is a no-op is worse than one that works.

`engineNameForTesting` reads the name off the instance. Everything needed to
answer the question exists; nothing shows it.

0463 is the precedent and the report was almost word for word the same — *"the
rust container is selected, but I have the strong feeling that it is not used at
all"*. It was being used; the runtime knew, the log knew, the Running Servers
window knew, and every one of those was somewhere somebody had to go. That item
put it beside the file, and showed the container rather than the local copy.

## Goals / Non-Goals

**Goals:**

- Somebody can tell, without restarting anything, which engine drew a pane.
- A pane older than the setting change says what it actually has.
- A fallback is heard once rather than found later.

**Non-Goals:**

- Changing when the engine is chosen, or letting it change under a live shell.
- A mark on every pane in the ordinary case.
- Making the engines behave the same. The declared gaps stay declared.

## Decisions

**Off the instance, never off the setting.** The setting is what somebody asked
for and the instance is what happened, and the whole item exists because those
two can differ in three ways. Reading the setting to draw this would reproduce
the bug in the report.

**The non-default engine is shown; the default is silent.** From 0463: a mark
that is present in the normal case is a mark nobody reads, and it costs the
strip space it does not have.

**Where it goes is the main decision, and it is left to the work** — the pane's
furniture, the tab's tooltip, or Running Servers and Containers. The item names
all three and prefers the last on 0463's reasoning; the tab strip is already
carrying a name, a running wash, a Claude badge and a close cross, and the
argument for adding to it is weakest.

**The fallback says something once, and it is not the same thing as the mark.**
"You asked for libghostty-vt and it would not start" is a sentence about a
moment; "this pane is drawn by X" is a state. Conflating them makes the state
noisy or the moment silent.

**The declared gaps are shown where somebody who turned it on will look.** The
engine already declares three — OSC 440, `modifyOtherKeys`, and tmux's prompt row
one line high — and they live in a source file. Somebody running the engine
deliberately is exactly the person who wants them; this is where that belongs, if
anywhere.

## Risks / Trade-offs

- **Another thing in the tab strip.** → Which is why the strip is the least
  favoured of the three places, and why only the non-default engine shows.
- **A fallback heard once may be missed.** → It is also visible in the mark
  afterwards: the pane says our emulator drew it, which is the durable half.
- **Two engines' names in the interface invites "which is better?"** → The
  answer is the point of the option: run it for weeks and report what differs.

## Open Questions

- **Does the mark belong to the pane or to the window?** A window with four panes
  can have two engines in it after a setting change.
- **Should the gaps be a list somebody can read, or a line each where they
  bite?** The second is better and much larger.
