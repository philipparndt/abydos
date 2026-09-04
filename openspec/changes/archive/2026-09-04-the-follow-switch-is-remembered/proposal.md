## Why

Reported: "when installing a new version the link terminal / project setting is
always disabled. We should remain the status."

It is not the installing. The control on the panel — the link circle beside the
terminal it is about — flipped the window's own copy of the switch and stopped
there. It never wrote the preference. So the two ways of turning following on
disagreed: the checkbox in Settings persisted, and the control anybody actually
reaches for did not. Every launch read the stored `false` and came back off,
and a new version is simply the launch somebody notices.

The other half is the same seam from the other side: ticking the box in
Settings while a window is open reached nothing, because no window re-read the
value. `Settings.set` posts `.abydosSettingsChanged` and `applySettings` did
not look at this one.

## What Changes

- **The panel's switch writes the preference**, so it survives a quit and the
  next window starts the way the last one was left.
- **A window adopts the stored value when *that* preference changes**, so the
  checkbox reaches an open window.
- **Only when it changes.** Every setting posts the same notification, and a
  window that re-read this on each of them would undo its own switch the next
  time somebody moved a font slider — the per-window switch is deliberate and
  stays.

## Capabilities

### Modified Capabilities

- `terminal`: following is remembered, and which of the two switches was used
  does not decide whether it is.

## Impact

- **AbydosApp**: `toggleFollowTerminal` writes the setting;
  `MainWindowController` remembers what the stored value was when it last
  looked, so "this preference moved" can be told from "some preference moved";
  `applySettings` adopts a changed one.
- **No migration.** The stored key is the one the checkbox has always written.
