# window-frame Specification

## Purpose

What the window does with its own size: what a zoom does, whose the standard
frame is, and what is remembered between sittings.
## Requirements
### Requirement: A zoom stays until it is undone

Double-clicking the title bar SHALL zoom the window and leave it zoomed, and
SHALL NOT return it to its previous size as part of the same gesture — whatever
the window's frame came from, including a frame restored from the autosave that
nobody has moved or resized in this sitting. Double-clicking again SHALL return
the window to the size it had before the zoom.

**It sprang back because the window was zoomed twice**, once by each of two
authors. The strip the app draws where the title bar would be answered the
second press of the gesture with `performZoom`; the second release, which the
strip forwarded to AppKit's frame view like every other mouse event, made AppKit
toggle the zoom straight back. Measured on 2026-09-09 from outside the process,
with real mouse events and the window server's own account of the bounds:
1280×820 to 1920×985 in a fifth of a second and back by half a second, every
time. Holding the second press for a second and a half held the two toggles a
second and a half apart.

The strip no longer zooms anything. AppKit handles the gesture alone, once,
under either SDK marker the binary is built with — measured under both.

The earlier measurement, on 2026-09-03, sent only the second press and release
into the window, so AppKit's title-bar handling was never armed by a first click
and the second toggle never fired. An instrument for this gesture sends all four
events, counted 1, 1, 2, 2.

#### Scenario: A window straight from the autosave

- **GIVEN** a window whose frame was restored at launch and neither moved nor
  resized since
- **WHEN** its title bar is double-clicked, as a mouse does it — press,
  release, press, release
- **THEN** it is zoomed once the animation is over, and still zoomed a beat
  after that

#### Scenario: Zooming back

- **GIVEN** a zoomed window
- **WHEN** its title bar is double-clicked
- **THEN** it returns to the size it had before the zoom, and stays there

### Requirement: The standard frame is AppKit's to choose

The app SHALL NOT implement `windowWillUseStandardFrame`, and SHALL leave the
frame a zoom aims at to AppKit.

**Tried, and it broke the other half of the gesture.** Returning the visible
frame of the window's own screen looks like the safer answer for a window with
`fullSizeContentView` and a title bar the app draws itself — and with it in
place a zoomed window could not be un-zoomed at all, reported from outside
within minutes. AppKit's own guess was already that visible frame; taking the
decision over broke the comparison `isZoomed` makes, and an un-zoom is a zoom
that knows it is zoomed.

#### Scenario: Un-zooming a window the app did not size

- **GIVEN** a zoomed window
- **WHEN** the gesture is repeated
- **THEN** it un-zooms, because AppKit is still the one deciding what zoomed
  means

### Requirement: The title-bar gesture is AppKit's to handle

The app SHALL NOT act on a double-click in its title strip itself — neither
zooming, minimising nor reading the system's setting for what the gesture
means. The strip SHALL forward mouse events to AppKit as any view does, and
AppKit SHALL do what the machine's setting says, as it does for every other
window.

**Two handlers is one too many, and the app's was the dispensable one.** A
handler was added on 2026-08-06 because the gesture appeared to do nothing;
from 2026-08-26 the installed binary is marked as built against the macOS 14
SDK, under which AppKit handles the gesture for a strip like this one on the
second release — and the app's handler, still acting on the second press, made
every double-click a zoom and an un-zoom. Measured with the handler switched
off, AppKit zooms once and stays, under the 14 SDK marker and the 26 alike.

#### Scenario: The system setting is not zoom

- **GIVEN** Settings ▸ Desktop & Dock says a double-click minimises, or does
  nothing
- **WHEN** the title strip is double-clicked
- **THEN** the window does what the setting says, because AppKit read it, and
  the app did nothing of its own

### Requirement: The strip's controls are no wider than what they do

A control in the title strip SHALL take only the room for the parts it acts
on when pressed. Anything the strip shows that is read rather than pressed —
the message about the last run — SHALL be drawn on the title bar itself, not
inside a toolbar item, so that a double-click on it or beside it zooms the
window as a double-click between the pills and the buttons does.

**Reported 2026-09-16 on 0.21.1.** The run control reserved room beside the
scheme well for the status of the last run, and a double-click there did
nothing, while one between the pills and the buttons zoomed. A narrow window
moves the capsule and the pills into the overflow menu before the run control,
leaving a strip that was all run control — and so a window that could not be
zoomed from its title bar at all. Forwarding the press, the release and the
drags from the control changed nothing, and neither did declaring the view
movable: measured with two builds side by side, the gesture works through the
toolbar's flexible space and never through a custom item, whatever the item
does with the events. So the room had to stop being the item's.

#### Scenario: To the right of the run buttons

- **GIVEN** a window whose title strip shows the run control
- **WHEN** the room to the right of the scheme well, or to the left of the
  buttons, is double-clicked as a mouse does it — press, release, press,
  release
- **THEN** the window is zoomed, once, and stays zoomed, exactly as it does
  from the room between the pills and the buttons

#### Scenario: A window too narrow for the capsule

- **GIVEN** a window narrowed until the capsule and the pills no longer fit
  beside the run control
- **WHEN** it is looked at
- **THEN** the capsule and the pills are folded away by the title bar, not put
  into a toolbar overflow menu, and the run control keeps the trailing edge
  with free strip beside it
- **WHEN** that free strip is double-clicked
- **THEN** the window is zoomed

#### Scenario: A window with less room than the capsule's maximum

- **GIVEN** a window with room for the capsule but not at its full width
- **WHEN** it is looked at
- **THEN** the capsule is shown at the room there is, its names shortened to
  fit, and the strip beside the run control is still free

#### Scenario: A status message beside the buttons

- **GIVEN** the message of the last run showing left of the buttons
- **WHEN** the message's text is double-clicked, away from the cross that
  clears it
- **THEN** the window is zoomed and the message is still there
- **AND** a single click on the cross still clears the message and zooms
  nothing

#### Scenario: A message arrives

- **GIVEN** a run that has just ended
- **WHEN** its message appears
- **THEN** the play and debug buttons and the scheme well are where they were

#### Scenario: The buttons are still buttons

- **WHEN** play, debug, the chevron or the scheme well is pressed
- **THEN** it does what it did before, and the window's frame does not change

