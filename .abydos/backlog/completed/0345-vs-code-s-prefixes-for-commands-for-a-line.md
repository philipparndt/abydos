# VS Code's prefixes: > for commands, : for a line

`99df48e19` · 2026-08-07

Both are typed into the same field, which is how VS Code does it and therefore
what hands already expect: a leading > narrows the list to commands, and a
leading : takes a number and puts the caret on that line of whatever is open.
The placeholder says so, since a prefix nobody knows about is a prefix nobody
uses.

`:` asks for the line rather than offering one: with no number yet it says so
in a row of its own, because a header with nothing under it reads as a list
that broke.

The empty needle has to be spelled out. Swift's contains("") is false, not
true, so filtering an action list on nothing returned nothing and a bare > sat
there under an Actions header with no actions beneath it.
