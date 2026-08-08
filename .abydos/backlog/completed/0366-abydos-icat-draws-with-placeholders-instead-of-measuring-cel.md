# abydos-icat draws with placeholders instead of measuring cells

`6c8995574` · 2026-08-07

The debug output said it: in Ghostty `cell 16x34px -> c=46 rows=30`, in
Abydos `cell 16x38px -> c=38 rows=22`. Both numbers are a guess at the
cell size read out of an ioctl, and everything hung off that guess — how
tall the picture is, and how far to move the cursor past it. Where the
guess is wrong the picture is followed by a field of blank lines, or
scrolls away before it can be looked at. Two terminals, two different
wrong answers, and no way to check either from here.

So it stops guessing. It transmits with `U=1` — a virtual placement,
belonging to no position — and then writes the picture as rows of
U+10EEEE placeholder cells, which is what kitty's own `icat` does and
why. The picture is exactly as tall as the rows written for it, because
it *is* those rows: there is no second number that has to agree, and the
cell size no longer decides the layout at all. It only decides the
proportions now.

It is also the form that survives tmux — the cells are text, so tmux
moves them and the picture with them — which makes the `$TMUX` branch
stop mattering for whether anything appears.

The diacritics are written by python3, resolved once with a fall back to
the one Xcode's tools install: a POSIX shell cannot emit a codepoint by
number, `printf '̅'` is not in bash 3.2, and /bin/sh here is bash
3.2.

A test asserts the placeholder count is exactly c × r and that there is
one newline per row — the property that makes the gap after an image
impossible rather than merely absent today.
