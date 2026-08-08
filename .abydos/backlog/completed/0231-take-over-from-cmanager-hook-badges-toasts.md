# Take over from cmanager: hook, badges, toasts

`3b92908fb` · 2026-08-03

ideai now learns what Claude sessions are doing the same way cmanager
did — from Claude Code's own hooks, which is the only honest source: a
pane running `node` looks identical whether it is thinking, waiting for
an answer, or done.

`ideai-hook` is a binary of its own rather than a subcommand of the app.
Claude runs it several times per tool call, and starting something that
links AppKit and a syntax engine to read one line of JSON is felt in
every session on the machine: 156 ms as part of the app, 22 ms alone —
and 134 ms of that gap was `Process.waitUntilExit`, which polls. The
pipe reaching its end is the child having gone, and no caller here asks
for an exit status.

It writes the same `@ai_status` window option cmanager wrote, so a tmux
status line that already shows it keeps working, and posts a distributed
notification the app turns into a toast: "docscanner needs you", amber,
one click to that tab — rather than a flash on tmux's status line that
is gone before anyone looks up. Every line names its window, including a
subagent's, because "a subagent finished" is a sentence about nowhere.

A subagent finishing no longer marks the window done, which is the thing
a tab-level state gets wrong: the session that sent it off is still
working. And the ⋯ is now an arc that turns, drawn by the strip rather
than an NSProgressIndicator per tab — the tab list is rebuilt twice a
second and controls would be created and destroyed with it.

`ideai-hook install` wires it into ~/.claude/settings.json: ours added,
cmanager's taken out, everything else in the file untouched, and a copy
of what was there kept beside it.
