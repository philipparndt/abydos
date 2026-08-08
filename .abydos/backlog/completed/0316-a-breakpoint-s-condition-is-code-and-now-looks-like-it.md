# A breakpoint's condition is code, and now looks like it

`f6d1c9ed0` · 2026-08-06

The options for a breakpoint were three text fields in the grey box an
`NSAlert` puts an accessory view in: title above, buttons below, and the part
that matters wedged between them looking like something unfinished. It is a
sheet of this app's own now — the line and the file it is in, three labelled
fields with an example beside each, and a note that an empty field is how a
condition comes off again, which nothing said before.

The fields hold code and are drawn as code, by the grammar of the file the
breakpoint is in: `stage == "local" && len(os.Args) > 1` arrives with its
string green and its numbers apart from its names. A log message is prose with
code in the braces, so only the braces are parsed — `stage is {stage}` reads
as a sentence with a value in it.

Two things this cost, both worth writing down. A text view that calls
`init(frame:)` without implementing `init(frame:textContainer:)` traps on the
way up, so the field is built through the initialiser that assembles the text
system. And a plain-text view paints its typing attributes over the storage:
nine tokens were found and none were visible until the colours moved to the
layout manager's temporary attributes, which is what those are for.

Verified by opening the sheet in a capture run — the values shown came back
out of the session file, which is the persistence from the last commit proving
itself in the app.
