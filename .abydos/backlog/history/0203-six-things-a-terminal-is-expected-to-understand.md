# Six things a terminal is expected to understand

`3a716784d` · 2026-08-03

All six asked for, all six now answered, with fifteen tests that drive the
sequences themselves.

**OSC 52 — the clipboard.** A copy made inside tmux, or on the far end of an
ssh connection, hands the text to the terminal and the terminal puts it on
the clipboard of the machine somebody is sitting at. Ours ignored it, so
those copies went nowhere. Writing only: a program asking to *read* the
clipboard is refused in silence, because anything that can run in a terminal
could otherwise take whatever was last copied, and that is a password as
often as not.

**The keyboard protocols.** Shift+Enter and Enter are the same byte; so are
Tab and Ctrl+I. A program that wants to tell them apart has to ask, in kitty's
form (`CSI > 1 u`, with a stack to push and pop) or xterm's older
`modifyOtherKeys`. Both are understood now, and only the genuinely ambiguous
keys go through them — sending every keystroke that way is correct by the
letter of the protocol and breaks every program that never asked. There was
already a comment in the parser about XTMODKEYS arriving from Claude Code and
being mistaken for SGR; it is a command now rather than a hazard.

**Focus reporting (1004).** `ESC [I` and `ESC [O` when the window gains or
loses the keyboard, so a full-screen program can stop animating while nobody
is looking.

**Colour queries (OSC 4, 10, 11, 12).** "What is your background?" is how a
program decides whether its own colours can be read against it. Unanswered,
it guesses — and guesses wrong on a light theme, which is worth having
settled before there is one.

**DECSCUSR.** vim in insert mode asks for a bar and a block there is a lie
about what typing will do. Shape is honoured; blinking is not, deliberately.

**OSC 8 — hyperlinks.** The text between the markers belongs to an address:
underlined under the pointer, opened by a click, and stored as a number per
cell with the addresses in a table, since a string per cell would cost more
than the text does.

And one that fell out of the last: the GPU renderer never drew underlines or
strikethrough at all. A man page's headings and a diff's struck-out text came
out plain. They are thin filled rectangles now, which is also what draws the
bar and underline cursors.
