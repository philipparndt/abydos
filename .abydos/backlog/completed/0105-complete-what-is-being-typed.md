# Complete what is being typed

`0bc0682d2` · 2026-08-01

A list under the caret after the second character of a word: ↑↓ to move,
return or tab to take one, escape to dismiss, and anything else keeps going
into the document so the list narrows as typing continues.

Two sources. Where a language server is running it is asked, because it
knows about types and scope; where there is none — or it has nothing to say
— the words already in the file are offered instead. That knows nothing
about anything, which sounds useless until you notice how much of typing is
repeating a name you wrote forty lines ago and would otherwise have to spell
exactly. The nearest use of a name wins, since the one you want is nearly
always the one you last looked at.

Never on the first character: a list after one letter is mostly noise. The
request is debounced for the same reason a server is not asked about text
nobody has finished writing.

The list is a borderless child window rather than a view in the editor, so
it can hang past the bottom edge and over the status bar, and it never takes
focus — the caret keeps blinking in the document and the keys keep arriving
there.
