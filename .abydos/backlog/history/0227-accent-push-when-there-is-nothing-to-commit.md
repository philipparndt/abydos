# Accent push when there is nothing to commit

`773e46a3a` · 2026-08-03

Commit and push sit side by side, and only one of them can be the primary
button — the accented one Return also triggers. Which one it should be is
not a matter of taste: with files staged the page is there to make a
commit, and with nothing staged the only thing left to do is send what is
already committed, so push takes the accent.

Decided on what is staged rather than on whether the commit button
happens to be enabled — a staged file with no summary typed yet is still
something to commit, and the accent should not jump to push and back
while somebody writes a message.
