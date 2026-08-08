# Stop making a keystroke wait for the next frame

`7eddc43b6` · 2026-08-03

It was not imagined: typing in the terminal was thirteen milliseconds
behind where it should have been, which is most of a frame — long enough to
feel unlike Ghostty and short enough to doubt yourself about.

Measured rather than guessed, with a probe that splits a keystroke into the
part that is the shell's and the part that is ours (IDEAI_INPUT_PROBE=1,
--type-latency N to drive it):

    before   echo 0.21   parse 2.69   draw 11.08   total 13.99 ms
    after    echo 0.19   parse 0.05   draw  1.09   total  1.33 ms

Two causes, both ours. Output waited two milliseconds to be read, a delay
that exists so a program painting the whole screen cannot starve drawing —
but a keystroke's echo is a handful of bytes with nothing behind it, and it
now goes straight through; the delay stays for a real backlog. Then the
frame waited for the next tick of the display link, up to sixteen more
milliseconds. That wait is worth it while output is pouring in, because
asking for a drawable blocks and everything queues behind it. When nothing
has been drawn for a frame or more there is nothing to coalesce with and the
drawable is free, so it draws at once.

Under load nothing changed, which is the point: seq 1 400000 still renders
60 frames a second, with the same parse time and the same wait for a
drawable. The fast path cannot be taken there — something is drawn every
frame, so it is never idle.

Same result through tmux (14.48 -> 1.60 ms) and on the CoreGraphics path.
What is left is the display itself: these monitors are 60 Hz, so the picture
still appears up to sixteen milliseconds after we hand it over. That part
belongs to everybody.
