## Context

`TerminalView.scrollWheel` turns a wheel event into something for the program
on two of its three paths — wheel reports when the program tracks the mouse,
arrow keys when it holds the alternate screen without tracking — and both count
steps with `Int(|Δy| / cellHeight) + 1`, capped at five. The third path, shell
output with scrollback, hands the event to the native scroll view and is at the
system's pace.

What arrives differs by device, and the formula knows only one of them. A wheel
raises one event per notch, `hasPreciseScrollingDeltas == false`, with a delta
near ten points and a larger one when spun — so one step a notch, five when
spun hard. A trackpad raises an event every eight to sixteen milliseconds while
the fingers move, `hasPreciseScrollingDeltas == true`, each carrying the points
moved since the last, and then a momentum phase of the same shape after the
fingers lift. The `+ 1` was there so a notch under a cell height is still a
line; applied to a trackpad it makes every two-point event a line. The scroll
view itself does none of this — it adds the points up — which is why the shell's
scrollback felt right to the reporter and `less`, `vim` and everything inside a
`tmux` with `mouse on` did not.

## Decisions

**Accumulate, and send whole cells.** `WheelSteps`, in the Kit, keeps a carried
remainder. A precise delta is added to it, `Int(carried / cellHeight)` steps
come out, and that many cell heights are taken off. Ten events of two points
against a sixteen-point cell produce one step after the eighth and carry four —
the same one line the finger moved. A hundred-point flick produces six steps and
carries four. There is no cap on the precise path: the distance is the finger's,
and momentum is what the native scroll view does too, so history and a full-screen
program now move at the same pace under the same gesture.

**A non-precise device keeps its formula, to the byte.** One step a notch, more
for a spun wheel, five at most. The maintainer reported no trouble with a mouse,
and a change he would feel is a change to something that was not broken.

**A reversal, or a new gesture, drops the carry.** Fourteen points carried
downwards followed by two upwards is two upwards, not twelve downwards; without
that, a finger changing its mind would be charged the old remainder before the
new direction registered. The view calls `reset()` when the event's phase is
`.began`, and the accumulator does the same itself when the sign flips.

*Ruled out: ignoring the momentum phase.* It would make a flick stop dead where
the fingers lifted, unlike every other scrolling surface on the machine, and it
would make the shell's scrollback and `less` move differently under the same
gesture — which is one of the two things the report is about.

*Ruled out: scaling the existing formula down for precise devices.* Dividing by
the event rate assumes an event rate; a Magic Mouse and a trackpad differ, and
Bluetooth batches. Adding the points up assumes nothing.

*Ruled out: routing precise events through the scroll view for the full-screen
paths too.* There is no document to scroll on the alternate screen; the events
have to become keys, and the question is only how many.

**Shift plus the four navigation keys, on the normal screen only.** ⇧⇞ and ⇧⇟
page, ⇧Home and ⇧End go to the ends. `TerminalKeys.scrollbackMotion(keyCode:shift:)`
says which motion a key is, and the view applies it when `isAlternateScreen` is
false; otherwise, and for the unshifted keys always, the key goes to the program
as before. This is the convention of kitty, Alacritty, GNOME Terminal and
iTerm2, and the reporter asked for keys, not for a particular key.

*Ruled out: the unshifted keys, as Terminal.app has them.* Plain ⇞ reaches
`less`, `vim` and an agent's own history today, and taking it would break paging
in the programs people scroll to read.

*Ruled out: ⌘↑ and ⌘↓.* Free today, but ⌘← and ⌘→ already mean start and end of
the *line* in this view, and a ⌘ arrow that moved the *view* while its neighbours
moved the cursor is two meanings on one modifier.

**A page is the pane less one row.** So the row at the bottom of one page is at
the top of the next and nothing is skipped past — the same overlap `less` keeps.
The pin follows from the position, through the bounds-change notification that
already computes `isPinnedToBottom` from where the clip view is, so ⇧End pins
and ⇧⇞ unpins without either being told to.

## What was measured, 2026-09-10

`less -N` on two thousand numbered lines in a driven pane, inside the machine's
own `tmux` with `mouse on` — so the wheel path is the mouse-tracking one, which
is the colleague's case. From a separate process, what a trackpad posts: ten
pixel-unit events of two points, then one of a hundred, at the pane. The line
number at the top of the screen is the claim.

| build | after ten events of 2 pt | after one event of 100 pt |
| --- | --- | --- |
| before | (not read separately) | top line **18** — seventeen lines |
| after | top line **2** — one line | top line **7** — five more |

Seventeen is the old formula exactly: ten for the ten small events, and
`Int(100 / cell) + 1` for the flick. Six is the new one: the twenty points of the
drag are one cell, sent when the tenth event completes it, and the hundred are
five — the pane's cell is a little over eighteen points tall, and the gesture
that began with the flick started from nothing carried. The `--mouse` report,
which gained a `WHEEL` line for this, shows every event as it was counted:

    WHEEL dy=-2.00 precise=yes phase=1 momentum=0 steps=0 program=yes
    WHEEL dy=-2.00 precise=yes phase=4 momentum=0 steps=0 program=yes
    …
    WHEEL dy=-2.00 precise=yes phase=4 momentum=0 steps=-1 program=yes
    WHEEL dy=0.00 precise=yes phase=8 momentum=0 steps=0 program=yes
    WHEEL dy=-100.00 precise=yes phase=1 momentum=0 steps=-5 program=yes

The zero-delta event that ends a gesture is the one that used to be a line down.

The keys, on the normal screen: four hundred lines of `seq` into a pane, then ⇧⇞
and ⇧End posted from outside, with the clip origin read at two-second marks.

| when | origin |
| --- | --- |
| before either key | 7011 |
| after ⇧⇞ | 6395 |
| after ⇧End | 7011 |

Six hundred and sixteen points is the 635-point clip less one row, and 7011 is
the bottom of a 7646-point document, which is where the bounds-change computes
the pin from.

One run of the fixed build, before the report existed, showed no movement at
all — the top line stayed 1 through both gestures. The run with the report
received and counted every event, and the code between the two runs differed by
the print alone, so that run's events did not reach the pane. Posting from
outside is a delivery, not a call; a run that shows nothing is asked again, with
the report on, before it is read as a result.

## Release note

**The terminal at a trackpad's pace, and keys for the scrollback.** A
full-screen program — `less`, `vim`, anything inside a `tmux` with the mouse on
— scrolled several lines for every event a trackpad raised, and a trackpad
raises a hundred a second: a slow drag of one line moved ten, a flick moved
hundreds. It moves by the distance the fingers covered now, with the fraction
carried between events, and a mouse wheel is exactly as it was. ⇧⇞ and ⇧⇟ page
back through a shell's output, ⇧Home and ⇧End go to the oldest line and back to
the prompt; on a program's own screen the keys reach the program as before.
