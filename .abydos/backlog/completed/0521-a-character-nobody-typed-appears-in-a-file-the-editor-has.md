# 521. A character nobody typed appears in a file the editor has open

`~/dev/abydos-examples/cadova-models/Sources/coaster/main.swift` line 16 reads

    C-ircle(diameter: diameter)

It should read `Circle`. A `-` is sitting inside an identifier, the file is
modified in that repository's working tree, and **nobody typed it there on
purpose**. It does not compile, so `CadovaExampleLiveTests` has been red for
every agent on this machine since it happened — which is how it kept being
found.

## The evidence, and it is better than usual

- **The file was modified at 21:22:20 on 2026-08-16** — one minute after the
  reporter's installed Abydos was started, and seventeen minutes before the
  first launch of any agent working in that area. 0518 established that
  timeline while chasing something else, and it is the reason this is filed as
  the app's doing rather than as somebody's slip.
- **It is not the only one.** 0517 found two more in the shell's own history,
  minutes apart on the same evening: `icd ..` — a `cd ..` with an `i` in front
  of it — and `mak einstall`, which is `make install` with the space one
  character early. Three stray characters, in two different views: two in a
  terminal, one in the editor.
- **0517 disproved the obvious cause.** `TerminalView.reportFocus` writes
  `ESC [ I`, and that was the hypothesis for the `i`. It is wrong four ways —
  measured in a real pty at seven arrival times, the character is a lowercase
  `i` where the report is `I`, the mode cannot be inherited, and in this
  machine's configuration the report is never written at all, because its
  terminals are tmux attaches and its tmux has `focus-events off`. That item is
  in `waiting/` for exactly this evidence.

## What this probably is not

Not the focus bug 0520 fixed, or not only that. That one sent ⇧⌘F's keyboard to
the rows instead of the query field — it explains typing arriving in the wrong
*pane*, and a character landing mid-identifier in a file the caret was not in
is a different shape. It is worth re-testing now that 0520 has landed, and this
item should start by asking whether it still happens at all.

## Where to look

- `CodeView.keyDown` and `insertText`, and `TerminalView.keyDown`'s two routes,
  which 0517 named as the place to start if a stray character ever appeared in
  the editor with nobody typing — which is what this is.
- Anything that replays or forwards a keystroke: an event handled by one view
  and passed on, a synthesised key press, a driver verb reachable in a normal
  run.
- **The launch-option drivers themselves.** Several of them type into the
  editor (`--type`, `simulateTyping`, the snippet and comment drivers) and this
  machine has been running dozens of app launches a day with them. A driver
  that types into whatever tab is in front, in a launch that also restored a
  session, would do exactly this. That is the first thing to rule out and it
  should be ruled out *by reading what the drivers do on an ordinary launch*,
  not by hoping.

## Steps

- [ ] Establish whether it still happens after 0520, and say so either way
- [ ] Rule the launch-option drivers in or out, by reading what they do when
      nobody passes them
- [ ] Find what writes a character into a file the caret is not in
- [ ] Fix it, or — if the cause turns out to be a driver nobody runs in
      ordinary use — write down plainly why the reporter's file was still
      changed by it
- [ ] Watched: the case that produced it, reproduced
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] The spec, if this changes what the project does

## Not part of this item

Restoring the file. `git -C ~/dev/abydos-examples checkout --
cadova-models/Sources/coaster/main.swift` puts it back, and that is the
reporter's call in their own repository — three agents have now reported it and
none of them touched it, which is right.

## Answered by 0522

The suspicion at the end of the description was right, and it was the drivers.

A run given a launch verb used to fall through to the most recently opened
project when none was named, and then restore that project's session. So a
typing verb ran against a window full of the reporter's own tabs, and the
character landed in the file that happened to be in front — which is how
`C-ircle(diameter: diameter)` came to be in `abydos-examples`, in a file nobody
was editing, a minute after a driven launch.

Nothing is wrong with the editor. Nothing writes a character into a file the
caret is not in: the caret really was in that file, because the window had put
it there on somebody else's behalf.

0522 fixes it three ways over — a driven run opens only what it was given,
restores no session, and refuses by name to type into a file it did not name.

## Closed without being done, 2026-08-17

Closed at the reporter's word, because 0522 found the cause and fixed it: the
harness. Every step below is left unticked, because none of them was carried
out — the answer did not come from this item's line of enquiry at all.

What is written above about what the fault is *not* stands, and cost the
afternoon it took to establish. That is the value left here.
