# Say what actually went wrong, in a dialog that can hold it

`e44280f8a` · 2026-08-02

An install that failed reported "DevPodInstall.Failure error 2" — helm's
own output was thrown away by a switch that did not know this kind of
error. It says what helm said now, and what to do when helm is missing.

The details behind a toast open in a panel of ours rather than a system
alert. What lands there is output — helm's, kubectl's, the compiler's —
and an alert reflows it into a paragraph with no way to read past the
twentieth line. Monospaced, scrollable, copyable whole.

Also: the console clears, from its context menu, with ⌘K as every
terminal does, and from a button beside the Console tab. And the branch
item leaves the toolbar when there is no branch instead of drawing a
one-point frame in the middle of the titlebar.
