# 2. Blank rows appear while the Return key repeats

Holding Return produces a full-width blank row between prompt lines,
irregularly. In tmux and in a plain tab.

**The emulator is not adding them. The shell is sending them.**

`Tests/AbydosKitTests/Fixtures/return-burst.bin` is 9075 bytes captured from a
live login shell — 45 presses, 33ms apart. Replay is deterministic. Split at
each `ESC[J`, the presses come in three shapes differing only in their tail:

    193 bytes: … \r space \r \r                    LF=1  -> 1 row
    197 bytes: … \r space \r \r\n \r\n \r          LF=3  -> 3 rows
    199 bytes: … \r space \r \r\n \r\n \r\n \r     LF=4  -> 4 rows

Rows consumed equals the line-feed count every time, which is correct. A
single-LF press replayed eight times gives eight adjacent prompt rows and no
blanks, on 4-, 6-, 12- and 30-row grids, so the scroll boundary is sound too.

Ruled out: a split-sequence parser bug (the same stream cut at every 7th byte
gives an identical grid), a data race (everything is on the main queue), and
an unclosed `pendingWrap` after a carriage return (`case 0x0D` clears it).

So the question is why zsh emits two or three extra line feeds per press. It
issues no cursor-position query anywhere in the capture, so it is not
reacting to an answer we gave. Leading candidate: it is reacting to terminal
state we set — a spurious SIGWINCH makes zsh redraw its prompt.

**Ask first:** do the blank rows appear in Ghostty with the same shell
config? If they do, this is the prompt's own behaviour and not ours.

---

Numbered 52 while it was being worked on, which is what a
commit message citing it means.
