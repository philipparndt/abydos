# The tmux bar settles darker, and its tabs read from across the room

`c8a8d539e` · 2026-08-04

Three passes at the dimming: too dim, still too dim, then too bright. This
is the one between — dark enough that the bar is a tone rather than a
colour, green enough that it is still tmux's bar.

At that darkness the inactive tabs needed the ink taking further than
"paler than the bar". A green only a little lighter than the green behind
it is a list you have to lean in for, and the tabs you are *not* in are
exactly the ones being read across.

Measuring the rendered bar rather than trusting the eye turned up the
thing worth fixing: at this dimming it lands at 0.419 luminance, and the
threshold that chooses between dark and bright ink was 0.42. It was
picking the right one by a thousandth — a slightly different theme green,
or a rounding difference, and the whole strip would have flipped to
near-black ink on a dark bar. Black only wins on a bar that is genuinely
light now.
