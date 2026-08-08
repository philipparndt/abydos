# A German keyboard can type a brace into a terminal

`d51ee3867` · 2026-08-06

Option was Meta, always. On a German layout that is where the characters a
programmer needs most are kept: `{` is ⌥8, `}` is ⌥9, `[` is ⌥5, `]` is ⌥6,
`|` is ⌥7, `@` is ⌥L. Every one of them sent an escape sequence instead —
⌥8 was `ESC 8` — so there was no way to get a brace into a shell but to paste
one, in an app whose whole claim is that the terminal is where the work
happens.

Two things wanted that modifier and the wrong one had it. A character the
keyboard says somebody typed is not a modifier gesture; word-motion is the
part worth making optional. So Option composes, as it does in every other Mac
terminal, and "Option sends Meta" is a setting for anybody who would rather
have ⌥B and ⌥F.

Checked through the key path rather than the rule alone — the rule was never
what was wrong, the question was which rule the view asked. ⌥8 sends `{`
(byte 123), and with the setting on it sends `ESC 8` again.
