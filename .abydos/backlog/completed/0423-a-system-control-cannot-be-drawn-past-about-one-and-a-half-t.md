# 423. A system control cannot be drawn past about one and a half times

The settings page follows the zoom now — it is rebuilt when ⌘+ is pressed, and
every control on it is told what size to draw at rather than only what font to
put inside it. Between 1× and about 1.4× that is the whole answer. Past it,
there is no answer AppKit can give, and this is where that was found out.

## What was measured

A bezel is drawn from `controlSize`, never from the font in it. Measured
directly on macOS 27, one control per line, `fittingSize` after layout:

    NSButton .accessoryBarAction  .small   font 11   →  91 × 20
    NSButton .accessoryBarAction  .small   font 22   → 148 × 20
    NSButton .accessoryBarAction  .large   font 22   → 156 × 28
    NSPopUpButton default         .regular font 12   → 188 × 24
    NSPopUpButton default         .regular font 24   → 302 × 24
    NSPopUpButton default         .large   font 24   → 310 × 28

The width follows the text. The **height does not move at all** for a bigger
font, and the whole range `controlSize` has to offer is 20 → 28 for a button
and 24 → 28 for a pop-up. `.large` is the largest artwork AppKit ships.

What the page asks for at 2× is a 24-point font, which wants a bezel of about
40 points. It gets 28. So:

- **At 1×** nothing changed and nothing should: `controlSize(.regular)` is
  `.regular`, which is what these controls already were.
- **At 1.25×–1.4×** the step up to `.large` is the fix — the artwork is drawn
  at a size that holds the type.
- **At 2× it is not fixed.** The pop-up is four points taller than it was and
  otherwise identical: the text still sits hard against the top edge of the
  bezel, and the chevron is still the small one, because AppKit is drawing
  `.large` artwork and stretching nothing. Screenshots of the gopls page at
  `-uiScale 2` before and after the change are indistinguishable.

## What is left, and the choice in it

The remaining fault is one control's worth of drawing, and there are only two
honest ways out:

1. **Accept it above ~1.5×** — say that the settings page is legible but not
   beautiful at a presentation zoom, and leave the bezels as they are. Costs
   nothing. This is what is in the tree today.
2. **Draw the controls** — a pop-up, a text field, a stepper and a slider of
   the app's own, the way `Sources/AbydosApp/Titlebar/PillButton.swift` and the
   language-server strip's buttons are drawn. Everything then scales exactly,
   and the page stops being the app's colours with the system's controls
   standing in them. It is also much the biggest of the three: a pop-up has to
   raise a menu, a field has to edit text and take a focus ring, and each of
   those is a thing AppKit was doing for us.

The language-server strip took route 2 on the same day and it was small there,
because those buttons are words and a glyph with no affordance to keep. A
pop-up is not that, which is why this is a decision rather than a task.

0418 hit the same shape of wall from the other side — a capsule that wants 60
points inside a titlebar that is 52 — and the right outcome there was to say so
rather than to reach for `.expanded`. Same here.

**Reproduce:** open settings, go to Tools → any tool, and compare
`-uiScale 1` with `-uiScale 2`. The "Installed on this machine" pop-up and the
"Custom image" field are the two to look at.

---

Its number is where it sits in the queue, not what it is worth doing next.

## Closed, without doing it

The owner's decision: **the zoom is good enough as it is.** *"Might find something
later but now it is ok."*

So the limit stands and is documented where somebody will meet it —
`Theme.controlSize(_:)` says a bezel is drawn from `controlSize` and never from
the font in it, with the measured numbers. What was rejected is the only fix
left: drawing the controls ourselves the way `PillButton` does, which is real
work for a zoom few people use, and which would be a second implementation of
every control the settings page has.

Reopen this if a large zoom becomes somebody's daily setting rather than an
occasional one. The measurements above are what to start from.
