## Why

`git log` in an Abydos pane prints everything and returns to the prompt. In
Ghostty, iTerm or Terminal.app it opens a pager, which is what somebody typing
`git log` is expecting — scroll, search with `/`, `q` to leave — and they get it
without configuring anything.

The cause is one line in the environment a pane is started with:

```swift
// Stop pagers from hanging a pane waiting for a keypress.
merged["PAGER"] = merged["PAGER"] ?? "cat"
```

Reported by a user, 2026-09-01, who found it by unsetting `PAGER` and watching
`git log` start behaving: *"Absicht?"* — intentional? Yes, and the reason has
expired. It was written when a pane could not be trusted with a full-screen
program; this terminal now claims `xterm-256color`, runs `vim`, `htop` and
`claude`'s own full-screen UI, and hosts tmux. A pager is exactly the class of
program it handles.

The default is also invisible where it hurts. Nothing on screen says `PAGER`
was set for you, and `git log` losing its pager reads as this terminal being
broken rather than as a decision somebody made. Worse, `PAGER=cat` is
inherited by everything the pane starts — including `git` invoked by scripts and
by tools that shell out — so it is not only `git log`.

## What Changes

- A pane no longer sets `PAGER`. What a program does when its output is long is
  the program's own default again: `git` opens `less` with its own `LESS=FRX`,
  which quits by itself when the output fits one screen, and `man`, `systemctl`
  and the rest behave as they do in every other terminal.
- What somebody has set themselves is still untouched — that half of the rule
  was always right and is now the whole of it.
- A tmux server that is **already running** has this app's old `PAGER=cat` in
  its global environment and hands it to every window it makes for the rest of
  its life — which is weeks. So the app takes its own footprint back out at
  launch: `PAGER=cat` in a running server's global environment is unset, and
  only that value, since anything else is somebody's own.
- Nothing else about the environment changes: `TERM`, `COLORTERM`, `LANG`,
  `TERM_PROGRAM` and the tmux and bundled-command variables are left exactly as
  they are.

## Capabilities

### Modified Capabilities

- `terminal`: an added requirement — the environment a pane is started with
  claims a capable terminal and does not disable the pager, said as a
  requirement because it is a promise about what a shell in here inherits and
  the old behaviour was found by a user rather than read anywhere.

### New Capabilities

<!-- none -->

## Impact

- **AbydosKit**: one line out of `PseudoTerminal.mergedEnvironment`, and the
  test that asserted `PAGER == "cat"` becomes the test that asserts nothing is
  set — the "what is already set wins" test stands unchanged.
- **AbydosApp**: nothing.
- **Risk**: a pager that waits for a keypress in a pane that cannot handle it
  would hang that pane. This is what the driven proof is for: `git log` in a
  pane, `q`, and the prompt back.
