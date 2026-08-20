## ADDED Requirements

### Requirement: A value beside the code can be opened up

A value drawn beside the code SHALL be openable where the variable it stands for
has children, into a window showing that variable with its fields under it.

`stage = "local"` is a whole answer at the end of a line. `mux = *net/http.ServeMux
{mu: sync.RWMutex {w:…` is a type name and forty characters cut mid-word, and a
struct does not fit at the end of a line at any budget — so what is needed is not
more characters but somewhere with room.

**Whether there is anything to open SHALL be the adapter's answer**, which is
`variablesReference > 0`, and not a guess made from the value's text. A hint that
can be opened SHALL show that it can before it is pressed, and one that cannot
SHALL do nothing when it is.

**Children SHALL be fetched on the gesture, never on a repaint.** A request per
hint per draw is what makes a stopped editor unusable; opening one is one
request, made because somebody asked for it.

The window SHALL expand and lazily load exactly as the variables tree in the
panel does, from one implementation rather than two, and SHALL be dismissed by
Escape, by a click outside it, and by execution resuming — a tree of values from
a program that is running again is worse than no tree.

**It SHALL be walkable with the keyboard and resizable.** A tree is read by
walking it: ↑ and ↓ move, → opens a row and ← closes it, which an outline view
answers by itself once it has the keyboard — so the window SHALL take the
keyboard when it opens, and expanding a row SHALL NOT lose what was selected.
Rebuilding the rows under a node drops a selection the view can no longer place,
so what is selected SHALL be remembered by the item rather than by the row. And a
struct is why the window exists, so its size SHALL be the reader's: it carries a
title bar to drag, edges to pull, and a close button.

The same SHALL be true of the panel's own tree, which knew the keys and never
received them: **clicking it SHALL give it the keyboard.**

Nothing about the line SHALL change: the same text, in the same place, truncated
the same way.

#### Scenario: a struct at the end of a line

- **GIVEN** a session stopped where `mux` is a `*net/http.ServeMux`
- **WHEN** the value drawn beside that line is clicked
- **THEN** a window opens on `mux`, showing its fields, each expandable

#### Scenario: something with nothing in it

- **GIVEN** the same stop, and `stage = "local"` on another line
- **WHEN** that value is clicked
- **THEN** nothing opens, and the click does what a click in the editor does

#### Scenario: it says which is which

- **GIVEN** both values on screen
- **THEN** the one that can be opened is distinguishable from the one that
  cannot, before either is clicked

#### Scenario: nothing is asked for until it is asked for

- **GIVEN** a file full of lines naming containers, scrolled through while
  stopped
- **THEN** no `variables` request is made for any of them
- **AND** one is made when a hint is opened

#### Scenario: walking it with the keyboard

- **GIVEN** a value opened up
- **WHEN** ↓ is pressed and then →
- **THEN** the selection moves to the field and the field opens
- **AND** what is selected is still selected once its children have arrived

#### Scenario: clicking the panel's tree

- **GIVEN** a stopped session with the variables tree showing in the panel
- **WHEN** a row is clicked
- **THEN** the tree has the keyboard, and the arrows walk it

#### Scenario: the program is let go

- **GIVEN** a value opened up
- **WHEN** execution resumes
- **THEN** the window goes, with the values beside the code
