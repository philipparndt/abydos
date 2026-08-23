## Why

**A Java edit costs a restart, and a restart costs everything the session was
for.** This app already debugs Java properly: `JavaDebug` builds launch and
attach requests, `JavaDebugHost` starts a jdtls for the debugger alone when the
project edits with the fast syntactic server, and a JVM in a pod is attached to
over JDWP through a port-forward — `JavaDebug.jdwpArgument` opens the port with
`suspend=y` so the interesting half of a service's life is not over before the
debugger arrives.

What none of it does is let a change reach the JVM that is already running. Fix
one line in a method and the only way to see it is to stop, rebuild, start again,
and get back to wherever you were — which for a service in a cluster means the
port-forward, the suspend, the first connection and whatever state took minutes
to build up. Eclipse and IntelliJ have both replaced method bodies in a running
JVM for twenty years, and it is the difference between debugging a service and
restarting one.

**Everything it needs is already here and unused.** The JVM has redefined
classes since 1.4 and reports whether it can; the adapter this app already speaks
to — the Eclipse java-debug bundle inside jdtls — carries the request that asks
it to; `DAPClient.request(_:arguments:)` takes an arbitrary command, so no new
plumbing is needed to send one; and `JavaDebugHost.buildWorkspace` already asks
jdtls to compile, because a launch needed compiling before it could find a class.
The pieces have never been put together.

No originating backlog item: the backlog was dropped on 2026-08-19, and this was
asked for on 2026-08-22.

## What Changes

- **Saving a file during a Java debug session builds it and redefines the
  changed classes in the running JVM.** The console says which classes were
  swapped, so a swap that happened is told from one that did not.
- **The same for a JVM that is not on this machine.** A session attached to a pod
  over JDWP swaps the same way — redefinition is the JVM's, not the launcher's,
  and the port-forward already carries it.
- **A refusal is reported in the JVM's own words, with a restart one press
  away.** HotSpot redefines method bodies and nothing else: adding or removing a
  method, changing a signature, adding a field or touching the hierarchy is
  refused, and that is most of what editing feels like. **Nothing restarts on its
  own** — a session holds a stack and a breakpoint somebody spent minutes
  reaching, and throwing that away without being asked is a worse surprise than
  the refusal.
- **Whether the JVM can do it at all is read and not assumed.** The capability
  comes from the adapter's own answer, and a JVM that cannot redefine says so
  once rather than failing on every save.
- **RCP applications are attached to, and their classes read from the build's own
  output.** `language-servers` already records that jdtls answers "no classpath"
  for an OSGi bundle, its dependencies being a target platform rather than
  anything in a build file — so an RCP app is launched however it is launched
  today, with JDWP open, and the swap reads the compiled classes from the
  bundles' output directories rather than asking a server that cannot answer.
- **Maven, Gradle and plain Java go through jdtls**, which is already the
  compiler on the launch path and already knows where each project's output
  directory is.
- **Not proposed: launching an RCP application.** It is refused today for a
  reason that has not changed, and solving it is a different change about target
  platforms.
- **Not proposed: DCEVM, JetBrains Runtime or any other enhanced-redefinition
  JVM.** They lift the method-body limit and they are somebody's choice of
  runtime, not this app's to require. What is proposed works on the JVM the
  project already runs.
- **Not proposed: dropping to frame after a swap.** A redefined method that is
  currently executing goes on running its old body until it is next entered;
  popping the frame to re-enter it is a second gesture with its own risks, and
  this change says plainly which of the two happened rather than doing the second
  quietly.

## Capabilities

### New Capabilities

<!-- None. Debugging Java is described by `debug-sessions` and by
     `language-servers`, and this is a thing a debug session can do. -->

### Modified Capabilities

- `debug-sessions`: gains what a session does with an edit while it is running —
  when a swap is attempted, what is said when it works, what is said when the JVM
  refuses, and that nothing restarts without being asked. Nothing it says today
  becomes untrue.
- `language-servers`: *Debugging Java does not depend on which server edits it*
  states what the debugger's jdtls is asked and that it answers nothing about any
  file. A swap asks it to compile, which is a third question and belongs in that
  list rather than quietly widening it.

## Impact

- `Sources/AbydosKit/Debug/JavaDebug.swift` — the request that asks for a
  redefinition, and the reading of what comes back.
- `Sources/AbydosKit/Debug/JavaDebugHost.swift` — `buildWorkspace` gains a
  caller that is not a launch, and the class files it produced have to be found.
- `Sources/AbydosKit/Debug/DebugSession.swift` — a session learns whether it can
  swap, and what to do with the answer.
- `Sources/AbydosApp/MainWindowController.swift` — a save during a session, and
  the report with the restart on it.
- `Sources/AbydosKit/Debug/DAPClient.swift` — untouched. `request` already sends
  any command, and `onEvent` already delivers any event.
- No new dependency, no new adapter, and nothing new installed on anybody's
  machine.
