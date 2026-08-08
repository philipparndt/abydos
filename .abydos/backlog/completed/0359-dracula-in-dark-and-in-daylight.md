# Dracula, in dark and in daylight

`9fbcbfc08` · 2026-08-07

A third palette beside Abydos and Blue, and the one people arrive with
rather than discover here — from a terminal, an editor, a whole desktop.
So the values are upstream's rather than adjusted to taste, and the six
accents keep the roles Dracula assigns them: pink for keywords, green for
functions, purple for constants and numbers, cyan for types, orange for
parameters, yellow for strings. Somebody who picks it should see the same
file in the same colours as in whatever they came from.

Every palette here comes in both lightnesses, and Dracula upstream is
dark only — but it does publish a daylight counterpart, Alucard, for
exactly the reason that inverting the dark one gives neon on white. That
is what the light half is: role for role with the dark one, in Alucard's
darkened hues on its warm off-white.

The terminal gets Dracula's own sixteen unchanged. Alucard publishes
eight hues rather than a table, so its bright half is each of them
lifted, which is what the dark scheme's bright half already is.

A test now asserts that every family names a terminal palette of its own,
since a family added without one falls back to blue — which is how
somebody ends up with a Dracula editor beside a terminal nobody chose.
