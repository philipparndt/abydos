## Context

`PanelTabStrip` draws both strips. `showsPanelControls` is true on the panel's
own strip, which carries the hide, maximise and follow buttons, the `tmux ·
session` tag and the sessions pill; it is false on the mirroring strip and in a
torn-off terminal window, where none of those things exist.

`recomputeLayout` places the trailing controls first and gives the tabs what is
left, then measures the run twice — once without the chevron and again with its
width taken off — and keeps `visibleRun`, `hiddenTabs` and
`overflowButtonFrame`. None of that is conditional on `showsPanelControls`, and
neither is the click or the menu.

## Goals / Non-Goals

**Goals:**

- The chevron on tmux's strip and in a torn-off window.
- A way to reach the state from a driven run.

**Non-Goals:**

- Changing what counts as hidden, how the run moves, or what the menu says.
  Those are `tab-overflow`'s existing requirements and they were already being
  met on these strips — invisibly.
- A ground behind the chevron. `tabRoom` reserves its width, so no tab reaches
  it; the ground under the panel's controls exists because tabs *do* run under
  those.

## Decisions

**The guard stays, and the chevron moves out from behind it.** The alternative
— dropping the guard and letting the panel controls draw from zero-width frames
— would rely on every one of them being harmless at `.zero`, which is a
property of five drawing calls that nothing states and nothing keeps.

**Drawn after the controls' ground and before the controls themselves.** The
ground fades in over the sixteen points in front of it, which overlaps the
chevron's trailing edge; drawn first, the chevron would be faded over. That
ordering is why the call cannot simply move to the top of the function.

**A seeded strip rather than a real tmux.** Standing a server up inside a driven
run does not reach the mirror in the seconds such a run lasts — the same reason
`seedUnclosableTabForTesting` exists. The seed makes the items the mirror makes:
numbered, unclosable, named as tmux names them.

## Risks / Trade-offs

**The seed is not the mirror** → It sets the items the mirror sets and nothing
else; what is being checked is the strip's own arithmetic and drawing, which
takes items and a width.
