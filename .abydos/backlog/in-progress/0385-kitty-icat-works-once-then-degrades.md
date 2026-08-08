# 385. kitty's own icat works once, then degrades

Two causes fixed in 8efac01: SGR `38:2:r:g:b` written with colons was not
read, so the placeholder cells carried no image id; and the APC cap of 8192
bytes truncated kitty's 131072-byte chunks, so the PNG never decoded. A
single run draws.

**Still wrong on repeat.** First run fine; the second shows the picture and
loses it while still reserving the space; the third blinks and does not even
reserve the space.

Established:

- The stream is not the variable. Three consecutive runs captured from a live
  terminal are structurally identical — `a=T,q=2,f=100,m=1,U=1,s=732,v=988,
  X=2,c=46,r=26,i=<different each time>` and a second chunk. No delete
  commands, no reused ids.
- The emulator handles all three. Replaying the captures back to back gives
  images 1,2,3 and virtual placements 1,2,3, with the placeholder cells
  resolving to 26, 39 and 39 placements — the drop accounting for rows
  scrolled off a 40-row screen.
- `ABYDOS_TERM_LOG=<path>` (e42eb08) records what the terminal was actually
  handed, which is not what `script` records: tmux and the line discipline
  both have a turn in between. A 715 KB capture of three runs shows all six
  graphics commands arriving intact, 22448 placeholder cells (tmux re-emits
  them on every repaint, which is the mechanism working), and only three
  `ESC[J` in the whole stream — so "the prompt erases the picture" is out.

**The open lead:** every placeholder row lands at screen column 62, not
column 0. 62 is exactly the width of the prompt on that line, and the drawn
images are visibly pushed that far right. The rows are separated in the
stream by `\r\n` and then padding spaces out to column 62, which is tmux
repainting content that genuinely sits there — so the offset originates
before this terminal, in what tmux believes about the cursor.

An image pushed 62 columns right is an image whose right-hand columns fall
off the pane, which is also what "images are cut off" looks like.

---

Numbered 50 while it was being worked on, which is what a
commit message citing it means.
