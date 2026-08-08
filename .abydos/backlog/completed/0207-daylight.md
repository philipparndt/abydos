# Daylight

`a398f21bd` · 2026-08-03

A light palette, and a setting that chooses dark, light, or whatever the
system is set to — the last being the default, since a machine that turns
dark at sunset should take the editor with it.

Not the dark theme inverted. A light interface wants more contrast in the
text and less between the surfaces, or every panel edge shouts; the greys sit
close together and the colours do the separating. The syntax palette is its
own: keyword blue, string green, call teal, all darker and more saturated
than their dark-theme counterparts, because a colour that reads against
near-black washes out against white.

The terminal scheme that follows the editor follows it here too — a terminal
that stayed black would be the one dark rectangle on the screen — with the
same hues darkened to be read against white. The Ghostty-blue scheme is
untouched: somebody who chose a palette chose it.

Switching applies at once rather than at the next launch, including when
macOS itself flips: the surfaces that keep their colour in a layer are handed
it again, and the app's own appearance goes with it so fields, scrollers and
alerts are not the last dark things left.
