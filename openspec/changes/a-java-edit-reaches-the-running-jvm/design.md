## Context

What is on disk already:

    JavaDebug.Request           launch and attach, in java-debug's wire shape
    JavaDebug.jdwpArgument      the -agentlib:jdwp flag, suspend=y, address=*:
    JavaDebugHost.startDebugSession   asks jdtls for a port over LSP
    JavaDebugHost.buildWorkspace      vscode.java.buildWorkspace, before a launch
    JavaDebugHost.classpath           java.project.getClasspaths
    DAPClient.request(_:arguments:)   any command, any arguments
    DAPClient.onEvent                 any event, with its body

The adapter is not a program beside the editor; it is an Eclipse bundle **inside**
jdtls, reached by asking the language server to start a session and connecting to
the port it answers with. `language-servers` records what follows from that, and
two of its findings shape this change:

- **jdtls is the compiler.** `buildWorkspace` exists because a launch was handed a
  correct classpath pointing at directories the server had not filled yet — 0452,
  found as a `ClassNotFoundException` from a project that was perfectly right. So
  the app already knows that a change on disk is not a class file until jdtls has
  been asked.
- **An OSGi bundle gets no classpath**, at once and for ever, because its
  dependencies are a target platform rather than anything in its build file. That
  is an answer and not a wait, and launching one is refused today.

**What the bundle actually offers**, read with `javap` from the copy on this
machine — `com.microsoft.java.debug.plugin-0.53.2.jar` and the
`com.microsoft.java.debug.core-0.53.2.jar` inside it — rather than from memory,
because three of this design's first decisions were wrong about it:

    request   redefineClasses, with RedefineClassesArguments — no fields at all
    response  changedClasses: String[], errorMessage: String
    event     hotcodereplace, body { changeType, message }
              changeType ∈ BUILD_COMPLETE | STARTING | END | ERROR | WARNING
    setting   DebugSettings.hotCodeReplace ∈ AUTO | MANUAL | NEVER,
              carried by the LSP command vscode.java.updateDebugSettings
    capability  none. Types$Capabilities has no hot-code-replace field.

And the part that decides most of this design: `JavaHotCodeReplaceProvider`
**implements `IResourceChangeListener`**. It watches the Eclipse workspace and
keeps `deltaResources` and `deltaClassNames` of what jdtls recompiled. That is
why the request takes no arguments — the adapter already knows which classes
changed, and there is no way to hand it one. It also carries `attemptPopFrames`,
`attemptDropToFrame` and `attemptStepIn`, so it re-enters an affected frame
itself.

The JVM side: `RedefineClasses` has been in JVMTI since 1.4 and HotSpot's
implementation replaces **method bodies only**. Adding or removing a method,
changing a signature, adding or removing a field, or changing the class hierarchy
is refused by the VM. A redefined method that is on the stack goes on running its
old body until it is next entered.

## Goals / Non-Goals

**Goals:**

- An edit to a method body reaches a running JVM without a restart, local or in a
  cluster.
- A refusal is legible: which class, what about the change, in the JVM's words.
- Nothing is thrown away without being asked.
- A project that cannot swap says so once, not on every save.

**Non-Goals:**

- Launching an RCP application, which is refused today for reasons this change
  does not address.
- Requiring DCEVM or JetBrains Runtime. What is built works on the JVM the
  project already runs; if somebody happens to be on an enhanced one, more of
  their changes are accepted and nothing here has to know.
- Dropping to frame, or re-entering a method that is currently executing.
- Kotlin, Scala or anything else on the JVM. jdtls compiles Java; the rest have
  their own compilers and are their own change.

## Decisions

**`AUTO` is this client's policy, not the adapter's behaviour — and that took a
running session to find out.** The name reads as "the adapter swaps by itself"
and it does not. The provider publishes `hotcodereplace` with `BUILD_COMPLETE`
when the workspace it listens to finishes compiling, and then **waits**:
`doHotCodeReplace` is reached only through the `redefineClasses` request. With
`AUTO` accepted and nobody sending that request, the log showed
`BUILD_COMPLETE` five times over five saves and never a `STARTING` or an `END`.

So the request is sent, and it is sent **on `BUILD_COMPLETE`** rather than on the
save. That answers the worry the paragraph below was written about: driving the
swap ourselves seemed to mean guessing when the compile had finished, and it does
not — the adapter says so, and that event is the cue. Setting `AUTO` still
matters, since it is what makes the adapter watch the workspace and raise the
event at all.

**What the design originally said, kept because the reasoning is still the half
that is right:**

**The adapter is put in `AUTO` and left to do it.** This is the decision the
reading changed. The loop already exists inside the bundle: in `AUTO` the
provider swaps whenever the workspace it is listening to gains new class files,
which is whenever jdtls finishes compiling. What is left for this app is to turn
it on, to ask for the compile on save, and to say what happened.

The alternative was `MANUAL` plus a `redefineClasses` of our own after each
build, and what rules it out is timing: the request swaps whatever deltas have
arrived *so far*, so sending it means deciding when the compile is finished —
which is exactly what the provider already knows by listening. Driving it
ourselves would be re-implementing that decision worse.

Ruled out: an explicit gesture only. It is more predictable and it is the wrong
default — a feature nobody remembers the shortcut for is a feature nobody has.
Ruled out for now: exposing `AUTO | MANUAL | NEVER` as a setting of this app's
own. The adapter has the three states and `vscode.java.updateDebugSettings`
carries them, so offering them later is a line of code; offering them now is a
preference invented before anybody has been annoyed.

**Nothing restarts on its own.** A refusal offers a restart and waits. The
session holds a stack, a breakpoint somebody spent minutes reaching, and — for a
service in a pod — a port-forward and whatever state the program built up. An
automatic restart is fastest exactly when it costs the most, and the failure mode
is silent: somebody looks back at a window that has thrown away the thing they
were looking at.

**There is no capability to read, so it is learnt from the first attempt.** The
design said the adapter reports what it can do in its answer to `initialize`; it
does not. `Types$Capabilities` has eighteen fields and none of them is about hot
code replace, so nothing can be asked ahead of time. What comes back instead is
either an `errorMessage` on the response or a `hotcodereplace` event with
`changeType: ERROR`, and both arrive only once something has been tried.

So the rule stands and the mechanism changes: a session learns it cannot swap
from the first refusal that is about the session rather than about the change,
and then stops saying it. Which is the harder half — telling "this JVM cannot
redefine at all" from "this JVM will not take *this* change" — and the two are
distinguishable only by what the message says. Where they cannot be told apart,
the message is passed through as it stands rather than being classified wrongly.

**A swap is build-then-redefine, and the build is jdtls's.** The app already
knows a change on disk is not a class file until jdtls has compiled it — that is
what `buildWorkspace` is for and why it is on the launch path. Doing anything
else would mean a second compiler with a second opinion about the classpath,
which is the two-servers-over-one-file argument that `language-servers` already
refuses.

Ruled out: watching the output directories and swapping whatever appears. It
would work and it would swap somebody's `mvn` run, a stale build, or a class from
a branch they just switched to. The swap should follow from the save it came
from.

**RCP reduces to one question that cannot be answered from here.** The plan was
to read the classes from the bundles' own build output and hand them over — and
there is nothing to hand them to. The request takes no arguments and the provider
reads the workspace itself, so either jdtls sees those bundles as projects and
their class files produce deltas, or it does not and there is nothing to swap.

**"No classpath" does not settle it.** That is what `language-servers` records
for an OSGi bundle, and it means jdtls could not resolve dependencies from a
build file — which is not the same as never having imported the project. An
imported project with an unresolvable classpath still has resources, and
resources are what the provider listens to.

So this is a *go and look* against a real RCP workspace, and it is not one this
machine has. Until somebody points it at one, the honest position is that Maven,
Gradle and plain Java are supported and RCP is untested — said in those words
rather than claimed either way.

Ruled out: a JDWP client of our own for OSGi, doing `RedefineClasses` with class
bytes read off disk. It would work regardless of jdtls and it is a second
debugger implementation to keep alive beside the one that already works, for one
project shape, before anybody has established that the first one fails.

**Which classes are sent is not this app's decision.** The design had it as one —
"only those the save could have changed" — and the request has no arguments. The
provider accumulates its own deltas from the workspace, so what is redefined is
what jdtls recompiled, and the concern the decision existed for (thousands of
classes for one edit) is already the adapter's to have.

What this app can still get wrong is asking for a *workspace* build when one file
changed, which is the same waste one step earlier. That is what task 5.2 measures.

## Risks / Trade-offs

- **Most edits are refused, and the feature reads as broken.** Adding a method is
  ordinary and HotSpot will not take it. → The report says *why* in the JVM's own
  words rather than "hot swap failed", and the restart is one press. The
  alternative — pretending it succeeded — is worse. This is the single biggest
  risk to the feature feeling good, and it is a property of the JVM.

- **A frame is re-entered without being asked.** The provider carries
  `attemptPopFrames`, `attemptDropToFrame` and `attemptStepIn`, so a method
  affected by a swap is dropped to and entered again — which the proposal had
  listed as *not proposed*, on the belief that it was ours to choose. It is not:
  it is what the adapter does. → It has to be *said*, because a stack that moved
  under somebody looking at it is worse unexplained than explained. The `END`
  event is where that is known.

- **`buildWorkspace` is a workspace build, not a file build.** On a project of a
  thousand bundles it may be slow, and it is on the save path. → The launch path
  already pays it once; whether it is affordable per save is a thing to measure,
  and `MachineLoad.said` beside the number. If it is not, the answer is a
  narrower build request rather than a different compiler.

- **Two builds racing.** Saves come faster than a workspace build finishes. → One
  build at a time with at most one queued, which is the shape `refreshGitStatus`
  already uses for the same reason.

- **A stale class for RCP.** Nothing compiles, so what is swapped is what the last
  build left. → Said, and the timestamps are readable: if the class file is older
  than the source, that is worth saying rather than swapping.

## What the reading found

The first task was to go and look, and it invalidated three decisions this design
had made from memory. They are corrected above; recorded here so the next reader
knows the design was wrong rather than assuming it was always this shape:

- **There is no capability** saying whether hot code replace is possible.
- **The request takes no arguments**, so which classes are swapped is not ours.
- **The adapter drops to frame** after a swap, which was listed as not proposed.

And one that did not survive: the RCP approach the change was proposed with —
class files from the build output — has nothing to hand them to.

## Open Questions

- **Whether a workspace build per save is affordable** on a project the size of
  the RCP one this app is used on. Measured before the trigger is settled, and if
  it is not, the trigger is not what changes — the build request is.

- **Whether jdtls imports OSGi bundles as projects.** The whole of whether RCP
  works, and answerable only against a real RCP workspace. Until then RCP is
  untested rather than supported or refused.

- **Whether "cannot redefine at all" is distinguishable from "will not take this
  change"** by anything but the text of the message. If it is not, the once-only
  rule is best served by passing the message through and not classifying it.
