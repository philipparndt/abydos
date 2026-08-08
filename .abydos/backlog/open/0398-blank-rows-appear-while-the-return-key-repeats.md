# 398. Blank rows appear while the Return key repeats

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

**Asked and answered: Ghostty does not do it**, with the same shell and the
same prompt. So the extra line feeds are zsh's, but something about this
terminal is what makes zsh send them — or what makes them land as blank rows
here and not there. It is ours.

Two ways it could have been ours, both now ruled out by reading:

- **A spurious resize.** `recomputeGridSize` returns before touching the pty
  unless the row or column count actually changed, so nothing sends `TIOCSWINSZ`
  or `SIGWINCH` for a redraw.
- **A scrollbar taking width.** That would change the column count as the
  document grows past the pane — exactly while somebody holds Return — but the
  terminal's scroll view is `scrollerStyle = .overlay`, so the clip's width
  never changes.

Which leaves the two halves of the question sharper than before. Either zsh is
reacting to something this terminal answers and Ghostty does not — the capture
shows no cursor-position query, so look at what is sent *unasked*: device
attributes, mode reports, focus events (1004), bracketed paste — or zsh sends
the same three or four line feeds to both and Ghostty absorbs one where this
does not. The second is worth testing first because it is cheap: replay
`return-burst.bin` into both and compare the resulting grids row by row, rather
than comparing what each looks like.

---

Previously numbered 52, 386.
