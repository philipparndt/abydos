# Abydos 0.4.0

Six commits since 0.3.1, and the reason for the number is the first item:
**a Java edit now reaches the JVM that is already running.** Fix a method body
during a debug session, save, and the program picks it up without restarting.

Two of the smaller items are fixes for things that had been failing in silence.
They are last, and they are worth reading if you have ever debugged Java here.

## Hot code replace, for Java

Change a method body while a program is being debugged, press ⌘S, and the running
JVM takes the new code. The process is not restarted: whatever state it had built
up is still there, the breakpoint you spent minutes reaching is still where it
was, and for a service in a pod the port-forward is still open.

    Build completed.
    Redefined com.example.hotswap.Greeting

The same works against a JVM you attached to. Redefinition is the JVM's own, so
where it is running has nothing to do with whether it works — the request travels
the connection every other debugger request already travels.

**Most edits will be refused, and that is the JVM rather than a fault.** HotSpot
replaces method bodies and nothing else: adding or removing a method, changing a
signature, adding a field and changing what a class extends are all refused, and
that is most of what editing feels like. When it happens you get the JVM's own
sentence about what it would not take, naming the class, with a restart one press
away. Nothing restarts on its own — a debug session holds a stack that was
expensive to reach, and for an attached session a restart is somebody's service
going down.

**The stack can move under you.** A method affected by a swap is dropped to and
entered again, so if you were stopped inside the method you just edited, you end
up at the top of its new body. That is the Eclipse debugger's behaviour and this
app does not turn it off; it says that it happened, because unexplained it reads
as the debugger losing its place.

Maven, Gradle and plain Java all go through the language server, which is already
the thing that compiles on the way to a launch. **OSGi and RCP are untested**
rather than claimed either way: whether they swap depends on whether jdtls
imports those bundles as projects at all, and that wants a real RCP workspace to
find out.

There is an example to try it on —
[`java/hot-swap`](https://github.com/philipparndt/abydos-examples/tree/main/java/hot-swap)
in the examples repository. It keeps count out loud, which is the point: a log
line tells you the new code ran and tells you nothing about whether the old
process is still the one running it. A counter that does not go back to one does.

## ⌃C stops a debug session from its console

A program printing into the debugger's console could not be stopped from it. The
only stop was closing the tab, which kills the program and takes away the output
saying what it did on the way down.

The console refused the keyboard entirely — the key was not ignored, it was never
delivered — so ⌃C now reaches it and stops the session, leaving the output where
it is and the tab open.

**It is not an interrupt.** That console owns no process: the program belongs to
the debug adapter, so what travels is the same request the Stop button makes and
no signal is sent. A program with a `SIGINT` handler will not run it. Saying so
here is the difference between understanding why your handler was skipped and
concluding it is broken.

⌘C still copies, which matters more than it sounds — a console that stopped your
program when you tried to copy a stack trace would be a trap. Shell tabs and Run
consoles are untouched: those are real terminals with a shell behind them and ⌃C
has always worked there.

## A Claude session that is running has a row

The **Claude Sessions** root arrived in 0.3.1 showing what past sessions left
behind. It was keyed on files, and a session that has been asked one question has
written none — Claude Code makes the scratch directory when a session starts and
writes into it only when a tool needs a temporary file. So the session you are
sitting in was the one the tree could not show you.

A session now gets a row when it left files **or** it is running. The one the
hook has spoken for says `running`; one known only by a recently-written
transcript is dated like any other row, because a timestamp cannot support the
stronger claim. It appears while you watch, rather than when the project is next
opened.

Sessions whose files went with a reboot still get no row. A row leading nowhere
is worse than an absence, and keying on transcripts would have put fourteen rows
on this project against two directories that still exist.

## The left rail says which pane is in front

Four buttons sat in one group at the bottom of the rail under three different
meanings of the same highlight, and two of them meant nothing at all. Opening the
backlog lit the *terminal*, because the terminal button was really saying "the
panel is open".

They now follow the rule the sidebar buttons already kept: lit when the panel is
showing that kind of pane, nothing lit when it is closed, and one button per pane
in front when the panel is split.

The debugger keeps what it had and gains what it was missing — it is lit when its
pane is in front *and* while a session is running with the panel closed, and a
running session colours it **green**, so the two can be told apart.

## Two things that were failing silently

Both were found while building hot code replace. Neither is new, and both matter
on their own if you debug Java here.

**The project was not being compiled before a launch.** Abydos asks the language
server to build before starting a JVM, because a classpath is a set of
directories the server fills after importing — that step exists to stop a launch
dying with `ClassNotFoundException` on a class that is perfectly correct. The
request was malformed and threw inside the server, into an error path that
discarded it, so it has never once run. It runs now.

**Saving a file never told the language server it had been saved.** Servers were
told what your buffer said on every keystroke, and never that the buffer had
become the file. For most servers that is invisible — they answer about the text
they were given either way — which is why nobody noticed. It is not invisible to
anything that builds: Eclipse compiles files, not unsaved editors, so a save left
jdtls with nothing to do.

Together those two are why hot code replace needed them fixed before it could
work at all.
