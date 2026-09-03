# Window Frame

## Purpose

What the window does with its own size: what a zoom aims at, that a zoom stays,
and what is remembered between sittings.

## ADDED Requirements

### Requirement: A zoom aims at the screen the window is on

The window SHALL answer for the frame a zoom uses, rather than leaving AppKit to
infer one: the visible frame of the display the window is on, which excludes
that display's menu bar and Dock.

A window with `fullSizeContentView` and a title bar the app draws itself is not
the shape AppKit's own guess is written for, and the guess is not stable across
a frame restored from the autosave.

#### Scenario: Zooming on the display the window is on

- **WHEN** the window is zoomed
- **THEN** it takes the visible frame of the display it is on

#### Scenario: A window on a second display

- **GIVEN** the window dragged to a second display
- **WHEN** it is zoomed
- **THEN** it takes that display's visible frame, not the first one's

### Requirement: A zoom stays until it is undone

Double-clicking the title bar SHALL zoom the window and leave it zoomed, and
SHALL NOT return it to its previous size as part of the same gesture — whatever
the window's frame came from, including a frame restored from the autosave that
nobody has moved or resized in this sitting.

Double-clicking again SHALL return the window to the size it had before the
zoom.

#### Scenario: A window straight from the autosave

- **GIVEN** a window whose frame was restored at launch and neither moved nor resized since
- **WHEN** its title bar is double-clicked
- **THEN** it is zoomed a moment later, and still zoomed a beat after that

#### Scenario: Zooming back

- **GIVEN** a zoomed window
- **WHEN** its title bar is double-clicked
- **THEN** it returns to the size it had before the zoom
