# A cursor that does not flicker, and tests that leave nothing behind

`6973c2142` · 2026-08-03

The cursor first. It is drawn filled where the keyboard is and outlined
where it is not — an outline says the cursor is still there and that typing
would go somewhere else, which vanishing does not. It never blinks: a blink
repaints the screen twice a second whatever the program is doing, and there
is nothing to gain when the cursor is already the only filled block on the
line. Losing the key window counts as losing focus, so switching apps
outlines it too.

Then the flicker, which the faster drawing exposed. A program repainting
hides the cursor, draws, and shows it again — three writes, and nothing says
they arrive in the same frame. Now that a frame can be drawn the moment
bytes are parsed rather than at the next tick, honouring the hide as it
arrives turns an ordinary repaint into a blink. A hide is now believed only
once it has outlasted a repaint, which is the difference between a cursor
that flickers and one that stays where you left it. Two smaller things
alongside: a frame is not taken while more input is waiting to be parsed,
and an inline frame is handed over inside a transaction of its own rather
than whichever one happened to be open.

Typing is still where it was: 1.65 ms through tmux, and no frame drawn
without a cursor in it.

And the preferences. Tests took a `UserDefaults` suite of their own and
removed the domain afterwards, which empties it but leaves the plist — and
cfprefsd writes it back after the process exits whatever the test does. This
machine had 3,682 empty ones, one for every test that had ever run. They are
gone, and the tests no longer make them: `UserDefaults` reads everything
through `object(forKey:)`, so a subclass holding a dictionary is a real one
as far as the code under test can tell, and it dies with the test. A full
run now leaves the preferences folder exactly as it found it.
