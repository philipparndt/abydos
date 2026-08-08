# Not every Claude notification is somebody being waited for

`3da1d0387` · 2026-08-03

"Compacting conversation…" was showing up as ⚠ needs-you, because the
badge was set on any Notification event at all. Claude sends those for
signing in, for a push going out, for compaction — and an amber badge
that appears when nobody is wanted is an amber badge people learn to
ignore.

The payload says which kind it is: `notification_type` is
`agent_needs_input`, `idle_prompt` or a permission prompt when somebody
really is being waited for, and `auth_success`, `push_notification` and
the like when Claude is talking to itself. The rest leave the badge as
they found it — a session that was working still is — and say nothing.
Versions that send no type fall back to the two sentences Claude uses
when it is waiting.

`IDEAI_HOOK_LOG=<path>` now records what the hook was actually handed,
so the next surprising badge is a file to read rather than an argument
about what the payload probably was.
