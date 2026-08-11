## MODIFIED Requirement: A pane says how large one of its cells is, and says so again when that changes

A program in a pane cannot measure a cell. The only place the size is written
down is the window size the kernel keeps for the terminal — `TIOCGWINSZ`
carries the grid in cells *and* the pane in pixels, and dividing one by the
other is how `icat`, `timg` and `chafa` decide how many cells a picture needs.
A terminal that leaves the pixels at zero is telling them it cannot show
pictures at all.

So the pane measures a cell in points from the font and multiplies by the
scale of the display it is on — pixels rather than points, because a picture
sized to a Retina cell and drawn at half of it is a soft picture where a sharp
one was asked for. Where there is no window yet, and there is not one when the
font is first measured, the screen is asked instead of a value being assumed:
assuming Retina on a display that is not one halves every cell, and kitty's
`icat` then asks for half the cells the picture needs.

And the number is told again whenever it changes. The window size is one
structure, so writing it used to be the business of a change in the number of
cells alone — which left a pane that learnt its real cell size after its
window appeared reporting the old one until something else happened to resize
it. The same command then produced a picture of one size on the first run and
twice that later, with nothing in between to explain it.

Because the number now reaches the program the moment it is worked out, an
answer that is wrong for a moment is an answer the program acts on. A scale of
zero is such an answer and is not an absent one: a window that is not on a
screen reports zero rather than nothing, and a window is not on a screen while
a display is being woken, unplugged, or moved between. So a scale is used only
if it is positive, and when none of the offered scales is, the size the
program already has is left alone rather than replaced by a guess — the last
answer was worked out on a screen that really existed.

What follows from the true number is not the pane's business to soften. A
picture taller than the pane scrolls as it is written, because `icat` sizes to
the width and never to the height; that is what kitty does with the same file,
and the way to see all of one is to ask for fewer rows.

### Scenario: a cell measured before there is a window

- **Given** a pane on a display whose backing scale is 1
- **When** its font is measured, before the view is in a window
- **Then** the program is told a cell is the size it is on that display,
  rather than twice it

### Scenario: the cell size changes without the grid changing

- **Given** a pane of 24 rows and 80 columns whose cell was reported as 8×19
- **When** the cell is found to be 16×38 and the grid is still 24 by 80
- **Then** the terminal reports 1280 by 912 pixels for the same 24 by 80 cells
- **And** the program is sent `SIGWINCH`, as it is for any other resize

### Scenario: a window that is not on a screen

- **Given** a pane whose window answers a backing scale of zero, and a display
  behind it whose scale is 2
- **When** the cell size is worked out
- **Then** the display's scale is used and the program is told 16×38
- **And** the program is never told a cell is zero pixels, which would be this
  terminal saying it cannot show pictures at all

## ADDED Requirement: A picture placed where there is not room for it makes the room

A program placing a picture at the cursor is told nothing about how tall the
pane is, and does not ask. `kitty icat` outside tmux sends the pixel size and
no number of rows at all, and leaves it to the terminal to work out how many
cells that comes to and to move the cursor past them. Making room for those
rows is therefore the terminal's part, exactly as it is when a program prints
that many lines: the rows above go into the scrollback, and the picture ends up
on the screen with the cursor below it.

Clamping the cursor at the last row instead — which is what a cursor *move*
does, and a picture's rows are not a move — leaves the picture standing on rows
below the bottom of the screen. Those rows are never drawn, so the picture is
invisible while the space it took is still spoken for. Worse, they overlap
everything a program erases from below the cursor, and a shell erases from its
prompt down before printing each one: the picture is taken away by the next
prompt. Both halves of "the picture is lost and the gap is kept" are that one
clamp.

This is the same rule the placeholder protocol gets for free. There, a picture
is spelled out in ordinary text and moves when the text moves; a picture placed
at the cursor has to be given the rows deliberately.

### Scenario: a picture taller than what is left below the cursor

- **Given** a pane of 10 rows with the cursor on row 8
- **When** a picture five rows tall is placed at the cursor
- **Then** the screen scrolls three rows, and three lines go into the scrollback
- **And** every row of the picture is on the screen

### Scenario: the prompt after such a picture

- **Given** a picture just placed where there was not room for it
- **When** the shell writes its next prompt, erasing from the cursor downwards
- **Then** the picture is still there
