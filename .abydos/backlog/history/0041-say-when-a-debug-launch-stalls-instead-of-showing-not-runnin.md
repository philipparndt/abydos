# Say when a debug launch stalls instead of showing "not running" for ever

`ebd25d589` · 2026-07-31

macOS holds a debuggee until its developer-tools authorization is
answered, and with developer mode off it asks every time. A dismissed or
unanswered prompt means the adapter never reports anything, and the
debug pane sat on "Not running" with no explanation — which is how a
system permission looked like a broken debugger.

A launch that produces no event within 25 seconds is now reported, with
the one-line fix (`sudo DevToolsSecurity -enable`) in the message. The
watchdog is generation-stamped so a stale one cannot fire on a session
that started after it.
