## Context

`PseudoTerminal.mergedEnvironment(_:bundled:app:inherited:)`
(`Sources/AbydosKit/Terminal/PseudoTerminal.swift:509`) builds the environment
before the fork — separated out on purpose so what it puts there can be checked
without starting anything, which is why this change is a one-line edit and two
test lines. It sets `TERM`, `COLORTERM`, `LANG` and `PAGER` as defaults (`??`),
and `TERM_PROGRAM`, `IDEAI_APP` and the tmux variables outright, each with a
recorded reason.

The `??` on `PAGER` looks like it defers to the user, and does not in practice:
`merged` starts from the *app's* environment, and a `PAGER` exported from
`.zshrc` is set by the shell that runs **inside** the pane, long after this
dictionary is handed to the fork. So the app's value is what `git` sees.

## Goals / Non-Goals

**Goals:**

- `git log` in a pane pages, as it does in Ghostty, with nothing configured.
- A pager somebody has chosen still wins.
- Proof that a full-screen pager is usable in a pane rather than a hang.

**Non-Goals:**

- No pager of our own, no `LESS` set for the user, no `core.pager` written into
  anybody's git config. The absence of a variable is the whole change.
- No setting. A toggle for "disable the pager in panes" is a setting nobody
  would find and whose off position is what every other terminal does; a user
  who wants `cat` writes `export PAGER=cat` where they write everything else.
- No change to the driven-run environment beyond what falls out of this: driven
  runs get the same environment, and a script that runs `git log` in a pane and
  waits for a prompt would now wait for `q` — see the risk below.

## Decisions

### Not set at all, rather than set to `less`

Ruled out: `merged["PAGER"] = merged["PAGER"] ?? "less -FRX"`. It reads as
helpful and is the same mistake one step along — `git` already defaults to
`less` with `FRX`, `man` has its own arrangements, and a pane that exports
`less` overrules a `core.pager` that somebody set deliberately. The correct
value for "behave like every other terminal" is no value.

### The reason for the old line is recorded as expired, not deleted

The comment "Stop pagers from hanging a pane waiting for a keypress" was true of
a terminal that could not run full-screen programs. Removing the line without
saying why leaves the next person to rediscover the fear. So the deletion takes
the reason with it into the requirement's own text: a pane runs full-screen
programs now, and that is what makes this safe.

### A running tmux server keeps the old value, so the app takes it back

tmux copies the environment it was started with into its global environment and
gives that to every window it makes afterwards. A server first started by an
Abydos pane therefore holds `PAGER=cat` for as long as it lives — the one on
this machine has been up since 28 August — and deleting the line that put it
there changes nothing for it. Measured, not assumed: with the line gone and a
clean launch, a pane on that server still reported `PAGER=[cat]`, and `git log`
still printed everything.

So `TmuxConfig.forgetPagerInRunningServer()` runs at launch: `show-environment
-g PAGER`, and if it is exactly `cat`, `set-environment -g -u PAGER`. Only
`cat`, because that is this app's own value and nobody sets `cat` deliberately;
only the global environment, because a session's is not ours; and only if a
server is already up, because starting one to clean it would be worse than the
mess.

Ruled out: telling the user to restart their tmux server. The app made the mess
in a place the user cannot see and would not think to look.

### The risk is a driven proof, not an argument

A pager *does* wait for a keypress, and a pane that mishandled it would hang —
which is the one thing worth checking rather than asserting. The proof is a
driven run: `git log` in a pane over a repository with more history than a
screen, a report that the pane is showing a pager (the `(END)` or `:` prompt is
in the pane's text), `q`, and a report that the prompt is back. A test of
`mergedEnvironment` alone would prove only that a dictionary lacks a key.

## Risks / Trade-offs

- [A driven script that runs `git log` and reads the pane now finds a pager
  waiting] → any such script in this repository is found by the suite; a script
  that wants no pager can say `git --no-pager log`, which is what it should have
  said.
- [tmux panes] → tmux passes the environment through; nothing here is tmux's.
- [A machine with no `less`] → `git` falls back to `cat` itself, which is the
  behaviour this change is handing back to `git`.

## Open Questions

- None. If a pane ever cannot host a pager again, the answer is to fix the pane.
