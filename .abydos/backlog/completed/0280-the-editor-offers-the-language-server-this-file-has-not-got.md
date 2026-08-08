# The editor offers the language server this file has not got

`4ec556f49` · 2026-08-05

An editor with no server for the language in front of you behaves exactly like
one whose server is broken. Nothing underlines, nothing completes, go-to-
declaration finds nothing. The only place that ever said why was the empty
state of a palette somebody had to think to open, and by then the conclusion
had already been drawn: this editor cannot do that.

So it says so where the file is, in a strip above it, in a sentence with the
command in it:

  💡 TypeScript has no language server. Install typescript-language-server for
     completion, problems and go-to-declaration.   [How to install] [Ignore] ✕

A strip rather than a dialog, for the reason the find bar is one: it never
covers the code, it can be read at a glance and ignored, and it costs a click
to be rid of rather than a click to continue. Three ways out, which is the
point — "not now" (✕, this window, this session), "not for this language,
ever" (Ignore, written down and answered the same in every project on the
machine, because the answer to "no server for JSON" does not change when you
open a different repository), and the one that solves it.

How to install opens the manual: what the server gives you, the one command,
and — the part nobody can look up — where the binary has to end up. An app
launched from the Dock inherits almost none of a login shell's PATH, so it
searches the PATH it has and then a fixed list of directories, and "it is on my
PATH" and "this app can find it" are not the same sentence. The panel lists
them, and says how to check.

It appears only when all of it holds: this language has a server, this project
is one that server understands, the server is not installed, and nobody has
said they do not want to hear about it. An editor that suggests installing what
you already have, or offers a Go server for the one stray .go file in a
TypeScript repository, is an editor people learn to ignore — so a stray file
gets nothing, and the bar goes away by itself once the server is there. Asked
again on every activation rather than cached, so installing it and clicking
back onto the code is enough; there is nothing to restart.
