## Why

A Claude Code session in one of the panel's own terminal tabs answered a
question, finished at 2:08, and a minute later the running-sessions pill turned
amber and its list read **abydos needs you · Claude is waiting for your input**.
Nothing was waiting. Claude Code sends a `Notification` of type `idle_prompt`
about a minute after every finished turn, and for a session in tmux the hook
already knows to ignore it: it reads the window's `@ai_status`, sees `done`, and
its rule says *nothing resurrects a finished turn*. Outside tmux the hook has no
window to ask and no memory of its own, so the same nudge falls through to the
plain rule, where an idle prompt counts as wanting an answer.

The hook has been wrong this way for as long as it has run outside tmux; the
toast said "needs you" a minute after every answer and was gone before anyone
compared notes. The pill made it stay on screen, which is how it was seen —
screenshot, 2026-09-02, the popover with the amber row beside the session's own
terminal showing `done 2:08 PM` and an empty prompt.

There is no originating `.abydos/backlog` item: this comes from a direct
report, 2026-09-02 — "I am wondering why I got 'is waiting for you' here".

## What Changes

- **The hook's payload carries the notification's type.** It already derives a
  status from it; now the type itself travels too, so a listener can tell an
  idle nudge from a permission prompt, which the derived status alone cannot.
- **The register applies the hook's own rule.** `RunningSessions` is the memory
  the hook lacks outside tmux — it held this session as `done` from its `Stop`.
  A nudge, or a subagent finishing, that arrives while the record says `done`
  leaves the record alone and reports no move. This is the rule
  `ClaudeHook.status(after:whenWindowSays:)` keeps for tmux windows, applied to
  the register's memory instead of tmux's.
- **The toast follows.** The register is consulted before the corner speaks; an
  event the register disregards is not announced either, so the corner stops
  saying "needs you" a minute after every answer outside tmux.
- A real question after a finished turn is unaffected: a permission prompt or an
  `agent_needs_input` still turns the row amber, and a session that was working
  when a nudge arrives still does — which is the case tmux also keeps.

## Capabilities

### Modified Capabilities

- `running-sessions`: gains a requirement that a nudge about a finished turn does
  not wake the session, on the pill, in the list, or in the corner.

## Impact

- **AbydosKit**: `ClaudeHookRunner.announce` adds one key; `RunningSessions`
  gains the rule and a query the watcher asks before announcing.
  `RunningSessionsTests` pins it against the real payload shape.
- **AbydosApp**: `ClaudeWatch.handle` asks the register before raising a toast.
- **Cost**: none — one dictionary lookup per event, on events that already
  arrive.
