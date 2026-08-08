# The numpad's Enter is a Return, not an interrupt

`3a0706a2a` · 2026-08-04

macOS hands that key over as U+0003 — End of Text, which is to say Ctrl-C.
Passed through as the character it claims to be, it interrupted: in a shell
it killed the line being typed, and in an agent's prompt it threw the
message away instead of sending it.

It is a Return, and every other terminal sends one. Named here alongside the
big one, so it carries the same carriage return and the same Option-as-Meta
rule. A program that genuinely needs to tell the two apart asks for the
keyboard protocol, which reports the key rather than the byte and is handled
before this table.
