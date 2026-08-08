# A picture sent in kitty's protocol is drawn on the grid

`859036ec3` · 2026-08-05

"The kitty protocol" is two things sharing a name. The keyboard one has been
here for a while — the flag stack, `CSI u`, the disambiguated escapes. The
graphics one, the escape that puts a real image on the grid, was being thrown
away: APC was consumed to ST and dropped, and that is exactly where a picture
arrives. So `icat`, `timg`, `chafa -f kitty` and matplotlib's kitty backend
all printed nothing at all.

Two things had to be true before any of the protocol mattered, and neither
was. The window size carried `ws_xpixel = 0`, and that is the only way a
program can learn how many pixels a cell is — every one of those tools reads
it and gives up when it is zero. `CSI 14/16/18 t`, the fallback for a program
that cannot read the ioctl or is on the far side of an ssh connection, was
unimplemented. Both are answered now, from a cell size the view hands down,
in real pixels rather than points so a picture arrives at the resolution the
screen can actually draw.

The protocol itself lives in `KittyGraphics.swift`, away from the emulator and
free of AppKit, because what makes an image right — where it lands, how many
cells it covers, which part of it shows — is arithmetic on bytes that arrived,
and none of it needs a window to check. Transmission direct, by file and by
temporary file; PNG through ImageIO and raw RGB/RGBA; chunked payloads and
zlib, which `Compression` almost has and `Run/Gzip.swift` already works around
from the other side. Placement with cropping, scaling and z-index; the delete
verbs; and the query handshake, which is the whole of how a program finds out
whether any of this is worth attempting.

Placements are anchored to absolute rows — the coordinate the dirty range and
the selection already use. That is what makes a picture scroll with the text
it was printed beside, survive into history, and come back when somebody
scrolls up to it; anchored to a grid row it would hang in place while the
output moved underneath. Lines falling off the front of scrollback shift them,
and one pushed past the start is forgotten rather than held forever.

Both renderers draw them, since the GPU one is a setting and the CoreGraphics
one is still the default. The GPU path needed a second pipeline and a texture
per picture: a picture is not a glyph, and packing megabytes into the atlas
would mean repacking it every time a program redrew. It also needed the cells
above a `z=-1` picture to stop painting their backgrounds — that path fills
every cell unconditionally, which is cheaper for text and would have painted
flat over anything behind it.

A `t=t` transfer says "delete this when you have read it" and can name any
path it likes. Only the scratch directories are ours to delete from.

Not here: Unicode placeholders, animation frames, shared-memory transfer. The
first is what carries images through tmux and is a piece of work in itself;
the other two are used by almost nothing.

Checked with the screenshot harness on both renderers — at native size, scaled
into a cell box, cropped, and behind text with the characters drawn over it.
