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

**This was measured rather than fixed.** It was reported as springing straight
back, and it does not: from a frame restored at launch and untouched, the
gesture took the window from 1280×820 to 1920×985, it was still there a beat
later, and a second gesture returned it to 1280×820 and left it there. No
behaviour in the app was changed to make that true.

What did produce the reported symptom, every time, was the instrument written
to look for it: a synthesised mouse-up carrying `clickCount: 2`, queued ahead
of its press, which AppKit read as a second double-click — so every gesture
zoomed twice. That is recorded in `MainWindowController+Zoom` beside the code
that must not do it again.

#### Scenario: A window straight from the autosave

- **GIVEN** a window whose frame was restored at launch and neither moved nor
  resized since
- **WHEN** its title bar is double-clicked
- **THEN** it is zoomed a moment later, and still zoomed a beat after that

#### Scenario: Zooming back

- **GIVEN** a zoomed window
- **WHEN** its title bar is double-clicked
- **THEN** it returns to the size it had before the zoom

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

