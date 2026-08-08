# A finished turn stays finished

`92ee9ae57` · 2026-08-04

The tab went amber moments after a turn ended. Claude Code sends a
"waiting for your input" notification when nobody has answered it yet,
and that arrives both when it has stopped mid-turn to ask something and
when it has simply finished and is sitting at a prompt. The badge was
being set from the event alone, so the second case overwrote a ✓ with a
⚠ — and a "needs you" that appears when nothing is needed is one people
learn to ignore.

Only the window itself knows which of the two happened, because only it
remembers what the badge said a second ago. The hook already asks tmux
where it is, so it now asks what the badge says in the same breath: an
idle nudge on a window that says "done" changes nothing and announces
nothing. Mid-turn it still means somebody is being waited for, and a
permission prompt counts whatever the tab said before.
