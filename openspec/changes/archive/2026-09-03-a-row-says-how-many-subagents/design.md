## Context

`ClaudeHook.parse` reads `hook_event_name`, `session_id`, `cwd`, `message`,
`notification_type` and `stop_hook_active` from the JSON Claude Code writes to
the hook's stdin. It does not read `tool_name`, because nothing has needed it:
the status a tab shows is derived from the event's name alone.

`SubagentStop` is already understood — it means "a subagent handed its work
back", it counts as the session still working, and it is deliberately not
allowed to resurrect a finished turn.

## Goals / Non-Goals

**Goals:**

- A row that says how many subagents a session has out, when it has any.
- A count that cannot drift upward for the life of a session.

**Non-Goals:**

- What each subagent is doing. The hook says nothing about that, and a list of
  a dozen sessions is not where a subagent's own prompt belongs.
- A count on the pill. The pill answers "is anything waiting for me" in two
  numbers and a third would dilute both.
- Reading the transcript for it. The register reads no disk, and that rule is
  worth more than this number.

## Decisions

**Counted from the two ends, and reset by the turn.** Up on a `PreToolUse`
whose tool spawns a subagent, down on `SubagentStop`, floored at nought, and
set to nought when a turn ends. The reset is what makes it self-correcting: a
missed `SubagentStop` — the app was not running, the hook failed, the subagent
was killed — would otherwise leave the count high for the life of the session,
and a number that only grows is worse than no number.

*Ruled out: counting only `SubagentStop`.* That is how many have finished,
which is not what was asked and goes stale in the other direction.

*Ruled out: inferring from the session's own status.* Nothing in `working`
says whether the work is being done by one agent or five.

**The tool's name comes from the hook and is compared to one string.** Claude
Code spawns a subagent with its `Task` tool, and `tool_name` is what the event
carries. If that name changes, the comparison stops matching and the count
stays at nought: the row then says nothing, which is what it says for a session
with no subagents. That is the safe direction to be wrong in, and it is why
this is not asserted as a fact about Claude Code but read from the payload.

*Ruled out: treating any `PreToolUse` as a subagent.* Every tool use would
count, so every working session would claim subagents.

**The row says it beside what the session last said**, in the same dimmed
trailing text as the line: it is a fact about the session's state, and the
title is the window it is in. Nought is not drawn.

## Risks / Trade-offs

**The count is only as good as the events** → It is reset by every finished
turn, so the worst case is one turn's worth of drift on a session whose events
went missing, and the next `Stop` clears it.

**A subagent that spawns a subagent** → Counted as two, which is what "how many
are out" means. Nothing in the payload says which parent it belongs to, and the
number a person wants is the total.

## Open Questions

- Whether the `Task` name holds across Claude Code versions. Unknowable from
  here; the failure is a count of nought, which the row does not draw.
