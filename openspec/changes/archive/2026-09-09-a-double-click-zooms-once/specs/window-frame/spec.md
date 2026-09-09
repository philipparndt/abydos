# Window Frame

## Purpose

What the window does with its own size: what a zoom does, whose the standard
frame is, and what is remembered between sittings.

## MODIFIED Requirements

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

## ADDED Requirements

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
