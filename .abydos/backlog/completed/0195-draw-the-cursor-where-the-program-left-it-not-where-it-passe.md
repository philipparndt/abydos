# Draw the cursor where the program left it, not where it passed through

`d5ee75cc4` · 2026-08-03

The flicker was the cursor being drawn mid-repaint. A full-screen program —
Claude Code in a tmux pane, in this case — hides the cursor, parks it
wherever is convenient for writing, draws, puts it back and shows it again.
Those writes need not arrive in one read, so a frame taken between them
shows the cursor somewhere it never really was. Both obvious answers are
wrong: drawing it where it is parked makes it jump about, and honouring the
hide for those few milliseconds makes it blink.

So while a program has the cursor hidden it stays where it last settled, and
only a hide that outlasts a repaint — a program that means it, like k9s —
takes it away.

Measured against a model of exactly that repaint, split across reads:

    before   115 frames, 55 with the cursor somewhere it only passed through
    after    118 frames,  3

And the fast frame is now for the echo of a keystroke and nothing else, once
per keystroke. Everything a program draws waits for the display's clock as
it always did, including the two milliseconds of gathering that turn one
repaint into one picture — which the last change had removed, and which is
why a program's stages were reaching the screen at all.

Typing is 4.5 ms on a quiet screen, 5.7 through tmux, against 14 before any
of this. While something else is repainting the screen sixty times a second
it is a frame like everybody else's: there is nothing to be idle for.
