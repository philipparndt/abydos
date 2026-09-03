## Why

A Claude session that has sent work off to subagents looks exactly like one
working alone. Claude Code says so in its own status line — `← 1 agent` — and
the running-sessions list, which exists to answer "what is happening where",
does not. Asked for on 2026-09-03: "it would be nice to see the amount of
subagents."

The hook already carries half of it. `SubagentStop` arrives when one finishes
and the app has handled that event since the badges were written; what is
missing is the other end, which is the `PreToolUse` that started it — and the
tool's name, which the payload does not send.

There is no originating `.abydos/backlog` item: this comes from a direct
report, 2026-09-03.

## What Changes

- **The hook sends the tool's name**, from the `tool_name` its own event
  carries, on the events that have one.
- **The register counts a session's subagents**: up on a `PreToolUse` for the
  tool that spawns one, down on `SubagentStop`, and back to nought when the
  turn ends — a finished turn has no subagents running, whatever was missed.
  Never below nought.
- **A row says how many**, when there are any: `2 subagents` beside what the
  session last said. A session working alone says nothing extra, because a
  count of nought is not news.
- **A wrong guess reads as nought, not as a wrong number.** The tool's name is
  Claude Code's to choose. If it names the spawning tool something other than
  what this expects, the count stays at nought and the row says nothing — the
  same as a session with no subagents, which is the safe way to be wrong.

## Capabilities

### Modified Capabilities

- `running-sessions`: the register's requirement gains the count, and the
  popover's requirement gains what a row says about it.

## Impact

- **AbydosKit**: `ClaudeHook.Event` gains `toolName` from `tool_name`;
  `ClaudeHookRunner.announce` sends it; `RunningSessions.Session` gains
  `subagents` and `note` keeps it. Tests against the payload shape.
- **AbydosApp**: the row's trailing text.
- **Cost**: none — one integer per session, moved by events that already
  arrive.
