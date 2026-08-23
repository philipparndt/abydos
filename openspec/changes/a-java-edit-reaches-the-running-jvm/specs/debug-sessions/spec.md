## ADDED Requirements

### Requirement: An edit reaches a JVM that is already running

Saving a Java source file while a debug session is running SHALL compile it and
redefine the changed classes in the JVM being debugged, without restarting it.

A restart costs everything the session was for: the stack, the breakpoint
somebody spent minutes reaching, and — for a service in a pod — the port-forward,
the suspend and whatever state the program had built up. The JVM has been able to
redefine classes since 1.4 and this app already speaks to an adapter that carries
the request.

**The compile is the language server's**, which is already true of the launch
path: a change on disk is not a class file until jdtls has been asked, which is
what `vscode.java.buildWorkspace` is on that path for. A second compiler would be
a second opinion about the classpath.

**Which classes are redefined is the adapter's to decide and SHALL NOT be
re-decided here.** The provider inside the bundle listens to the workspace and
keeps its own record of what was recompiled, which is why the request carries no
arguments and why there is no way to hand it a class file. What this app controls
is asking for the compile; what is swapped follows from what that compile wrote.

**A swap SHALL say which classes were swapped.** A swap that happened has to be
tellable from one that did not, and silence looks the same as both.

#### Scenario: a method body changed during a session

- **GIVEN** a Java debug session stopped or running
- **WHEN** a method body is edited and the file saved
- **THEN** the project is compiled and the changed class is redefined in the
  running JVM
- **AND** the console says which class was swapped

#### Scenario: no session running

- **GIVEN** a Java project with no debug session
- **WHEN** a file is saved
- **THEN** nothing is compiled for a swap and nothing is redefined

#### Scenario: a file that changed nothing

- **GIVEN** a running session
- **WHEN** a save produces no changed class file
- **THEN** nothing is redefined, and nothing is said about a swap

### Requirement: A JVM that will not take a change says why, and offers a restart

Where the JVM refuses a redefinition, the refusal SHALL be reported in the terms
the JVM used, naming the class, and a restart of the session SHALL be one press
away.

**HotSpot redefines method bodies and nothing else.** Adding or removing a
method, changing a signature, adding or removing a field, and changing the class
hierarchy are all refused — and that is most of what editing feels like, so this
is the ordinary case rather than the exceptional one. A report that says only
"hot swap failed" teaches somebody to ignore it; one that says *added method:
validate(Order)* tells them exactly why they are about to restart.

**Nothing SHALL restart on its own.** The session holds a stack and a breakpoint
that were expensive to reach, and an automatic restart is fastest exactly when it
costs the most. The offer waits.

**A swap that moved the stack SHALL say so.** The adapter drops to an affected
frame and enters it again rather than letting the old body run to its end — it
carries `attemptPopFrames`, `attemptDropToFrame` and `attemptStepIn`, and this is
not behaviour this app chose or can decline. A stack that moves under somebody
who is looking at it is the most confusing thing hot code replace does, and
unexplained it reads as the debugger losing its place.

#### Scenario: a method added

- **GIVEN** a running session
- **WHEN** a method is added to a class and the file saved
- **THEN** the refusal names the class and what about the change was refused
- **AND** the session is still running, on the same stack
- **AND** a restart is offered and not taken

#### Scenario: the restart is taken

- **GIVEN** the offer above
- **WHEN** the restart is chosen
- **THEN** the session restarts, and for an attached session reattaches

#### Scenario: a swapped method that is on the stack

- **GIVEN** a session stopped inside a method
- **WHEN** that method's body is edited and swapped
- **THEN** the frame is entered again by the adapter, and that it happened is
  said

### Requirement: A session that cannot swap says so once and stops trying

Where a session turns out not to be able to redefine classes at all, that SHALL
be said once and SHALL NOT be said again on every save.

**Nothing can be asked ahead of time.** The adapter reports eighteen capabilities
in its answer to `initialize` and none of them is about hot code replace, so
whether it is possible is knowable only from what comes back after something has
been tried. A saved file that can never be swapped must not produce a failure
each time: a message on every save is a message nobody reads, including the one
time it is about something else.

**A failure about the session SHALL be told from a failure about the change**,
and where the two cannot be told apart the message SHALL be passed through as it
stands rather than classified wrongly. A change HotSpot refuses is ordinary and
says nothing about the session; a session that cannot swap at all is a different
sentence and is the one that silences the rest.

#### Scenario: a session that cannot swap

- **GIVEN** a session whose first swap fails for a reason that is about the
  session rather than about the change
- **WHEN** a file is saved again
- **THEN** it was said once, and later saves say nothing

#### Scenario: a refusal that is about the change

- **GIVEN** a session that has swapped successfully before
- **WHEN** a change the JVM refuses is saved
- **THEN** it is reported, and the next save is still attempted

### Requirement: A JVM in a cluster is swapped the way one here is

A session attached to a JVM over JDWP SHALL swap exactly as a session that
launched one does.

Redefinition is the JVM's own, so where the debugger is running has nothing to do
with it: the request travels the connection that carries every other debugger
request, which for a pod is the port-forward this app already opens with
`suspend=y`. What differs is what happens when the JVM will not take it — a
remote restart is a restart of somebody's service — so the offer names what it
will restart.

#### Scenario: a method body changed against a pod

- **GIVEN** a session attached over JDWP to a JVM in a pod
- **WHEN** a method body is edited and saved
- **THEN** the class is redefined in that JVM, and the console says so

#### Scenario: a refusal against a pod

- **GIVEN** the same session, and a change the JVM refuses
- **THEN** the refusal is reported as it is locally
- **AND** what a restart would restart is named before it is offered

### Requirement: An OSGi project is not claimed to swap until it has been tried

Where a project's classes are not ones the language server compiles, a swap SHALL
NOT be claimed to work, and SHALL NOT be claimed to be impossible either.

This change was proposed with RCP taking its classes from the bundles' own build
output, and there is nothing to give them to: the request carries no arguments
and the provider reads the workspace itself. So whether an OSGi project swaps
reduces to whether the language server imported its bundles as projects at all —
if it did, their class files are resources like any other and nothing extra is
needed; if it did not, no swap can reach them.

**"No classpath" does not settle that question.** It is what jdtls answers for a
bundle whose dependencies are a target platform rather than a build file, and it
means dependencies could not be resolved — not that the project was never
imported. The two are different and only one of them stops a swap.

Until it has been tried against a real one, an OSGi project SHALL be described as
untested rather than supported or refused, and a swap that finds nothing to do
SHALL say that nothing was recompiled rather than that the change failed.

#### Scenario: a swap that finds nothing

- **GIVEN** a session against a project the language server did not compile
- **WHEN** a file is saved
- **THEN** it is said that nothing was recompiled
- **AND** it is not reported as a failed swap
