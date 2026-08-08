# Let the bell's colour channels actually come apart

`ef63bdb0d` · 2026-08-01

The fringing was there in principle and invisible in practice. Each channel
was sampled a little off the glyph and then clamped back inside it, so
instead of sliding off the letter it smeared the edge pixel sideways — which
reads as a slightly soft glyph, not as a colour split.

A sample outside the glyph's slot now reads as no ink rather than being
pulled to the edge, which is what lets a channel slide off and leave a
coloured ghost behind. With that fixed the shift can be six times what it
was without the artefacts that forced it down in the first place.
