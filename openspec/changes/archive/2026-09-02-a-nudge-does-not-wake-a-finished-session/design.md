## Context

`ClaudeHook.status(after:whenWindowSays:)` is where the tmux case is right: a
`Notification` whose type is `idle_prompt`, or a `SubagentStop`, arriving while
the window says `done` returns nil, and the tab keeps its tick. The "window says"
half is `@ai_status`, read by the hook from the pane it runs in. Outside tmux
there is no pane, `place` is nil, and `whenWindowSays: nil` is the plain rule —
in which an idle prompt is somebody being waited for.

`RunningSessions` now remembers each session's last status, from the same
events. It knew this session was `done`.

## Goals / Non-Goals

**Goals:**

- A nudge about a finished turn changes nothing: not the pill, not the row, not
  the corner.
- The same rule in both places, so a tmux tab and a plain terminal tab agree.

**Non-Goals:**

- Teaching the hook to remember. It is a process that lives for milliseconds;
  the register is the memory and is already in the right place.
- Dropping every nudge. A session that was *working* when the nudge arrives is
  genuinely waiting — Claude paused mid-turn for an answer — and that stays
  amber.

## Decisions

**The type travels, not a verdict.** The payload gains `notificationType`, the
raw field, rather than a boolean the hook computes. The hook cannot compute the
verdict outside tmux — that is the whole fault — and a raw field lets the
register apply the same `isIdleNudge` test the hook uses, from the same string.

*Ruled out: matching the message text.* "Claude is waiting for your input" is
one of two sentences the hook already falls back to for old Claude versions
that send no type; matching it here would be a second copy of a fallback, in
the place that has the real field available.

**The register decides, and the watcher asks it first.** `note` applies the
rule while it has the record in hand — the status stays `done`, the event is
recorded as heard, no move is reported. The toast needs the same answer before
`note` has run, so `disregards(_:)` is a pure query on the current state that
`ClaudeWatch` asks, then calls `note`, then returns without announcing.

*Ruled out: `note` returning a third answer.* It answers "did anything move";
"and also do not toast" is a different question, asked by one caller.

**`SubagentStop` after `done` is treated the same**, because the hook treats it
the same and for the same reason: a subagent handing back work after the turn
that sent it off has ended is not the session starting again.

## Risks / Trade-offs

**A session finishing while the app was not running has no `done` record** →
Its nudge is then taken at face value, as before. It is one nudge, once, and the
alternative — guessing from the message — is the fallback ruled out above.

**Older Claude Code sends no type** → Then the field is absent and the rule does
not fire; behaviour is as today. The hook's own text fallback still derives the
status for the tab.
