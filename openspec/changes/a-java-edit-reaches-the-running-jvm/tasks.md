## 1. What the adapter actually offers

**Done, and it invalidated three of the design's decisions.** Read with `javap`
from `~/.local/share/java-debug/com.microsoft.java.debug.plugin-0.53.2.jar` and
the `com.microsoft.java.debug.core-0.53.2.jar` inside it:

    request   redefineClasses — RedefineClassesArguments has NO fields
    response  changedClasses: String[], errorMessage: String
    event     hotcodereplace { changeType, message }
              changeType ∈ BUILD_COMPLETE | STARTING | END | ERROR | WARNING
    setting   DebugSettings.hotCodeReplace ∈ AUTO | MANUAL | NEVER,
              carried by the LSP command vscode.java.updateDebugSettings
    capability  none — Types$Capabilities has eighteen fields and no HCR one

`JavaHotCodeReplaceProvider implements IResourceChangeListener` and keeps its own
`deltaResources` / `deltaClassNames`: it watches the workspace, which is why the
request takes no arguments. It also carries `attemptPopFrames`,
`attemptDropToFrame` and `attemptStepIn`, so it re-enters affected frames itself.


- [x] 1.1 **Find out and write down what it is called.** The Eclipse java-debug
      bundle carries both the redefinition request and a capability saying whether
      it is possible; the names are read from the `initialize` answer and from the
      adapter's own source, not from memory. The design's first open question, and
      the first thing to be true before anything else is built.
- [x] 1.2 Whether the adapter reports the capability at all, and whether it
      distinguishes "this JVM cannot" from "this adapter cannot". They are
      different sentences to somebody attached to a pod.
- [x] 1.3 What comes back from a refusal: whether the class and the reason are in
      the response, an event, or both. The whole of the report depends on it, and
      "hot swap failed" is the thing this must not end up saying.
- [x] 1.4 Recorded where the next person finds it — in `JavaDebug`, beside
      `startCommand` and `buildCommand`, which is where the other three commands
      this app depends on are written down and explained.

## 2. Asking for it

- [x] 2.1 `JavaDebug` gains the request in the adapter's wire shape, beside
      `Request.wireFormat`, and the reading of what comes back — swapped classes,
      refusals, and which class each names.
- [x] 2.2 Nothing new in `DAPClient`. `request(_:arguments:)` already sends any
      command and `onEvent` already delivers any event; if either turns out to be
      insufficient, that is a finding worth writing down rather than a change to
      make quietly.
- [x] 2.3 Tests over the real payload shapes, the way `ClaudeHookTests` covers the
      hook's: a swap that worked, one refused for an added method, one refused for
      a changed signature, and an empty set of classes.

## 3. Which classes, and from where

- [x] 3.1 **Not ours to decide, and that is the finding.** The request has no
      arguments; the provider keeps its own deltas from the workspace. Nothing to
      build here, and the design and spec now say so rather than claiming a
      choice this app does not have.
- [x] 3.2 For Maven, Gradle and plain Java: `JavaDebugHost.buildWorkspace` gains a
      caller that is not a launch. Finding the class files afterwards is the
      adapter's job, not this one's.
- [x] 3.3 For OSGi: nothing extra to build, and nothing to claim. Whether it
      works is whether jdtls imported the bundles at all, which needs a real RCP
      workspace to find out — this machine has none. A swap that finds nothing
      recompiled says so rather than reporting a failure.
- [x] 3.4 Dropped with the RCP approach it belonged to: no class file is chosen
      by this app, so none can be checked against its source.
- [x] 3.5 One build at a time with at most one queued, the shape `refreshGitStatus`
      uses: saves come faster than a workspace build finishes.

## 4. Saying what happened

- [x] 4.1 The console says which classes were swapped. A swap that happened has to
      be tellable from one that did not.
- [x] 4.2 A refusal names the class and what about the change was refused, in the
      JVM's words. **This is the requirement most of the feature's usefulness
      rests on**: adding a method is ordinary and HotSpot will not take it, so the
      ordinary case is the refusal and it has to read as an explanation rather
      than a failure.
- [x] 4.3 The restart is offered and waits. Nothing restarts on its own, and for
      an attached session what a restart would restart is named — it is somebody's
      service.
- [x] 4.4 A method that is on the stack when it is swapped says that the new body
      takes effect when it is next entered. The confusing case, named rather than
      discovered.
- [x] 4.5 A session that cannot swap says so once and then stops offering. A
      message on every save is a message nobody reads, including the one time it
      is about something else.

## 5. The trigger

- [x] 5.1 `AUTO` is set on the session through `vscode.java.updateDebugSettings`,
      and a save during a Java debug session asks for the build. The swap itself
      is the adapter's, triggered by the compile finishing rather than by us
      guessing when it has. A save with no session does nothing and costs
      nothing.
- [ ] 5.2 **Measure the build before settling this.** `buildWorkspace` is a
      workspace build and this app is used on a project of a thousand bundles. If
      a build per save is not affordable, what changes is the build request and
      not the trigger — and either way the number is recorded with
      `MachineLoad.said` beside it, since a number without the load cannot be told
      from a regression.
- [x] 5.3 No setting of this app's own yet. The adapter has `AUTO | MANUAL |
      NEVER` and `updateDebugSettings` carries them, so offering them later is a
      line; offering them now is a preference invented before anybody has been
      annoyed.

## 6. Something to try it on

- [x] 6.0 **`java/hot-swap` in `abydos-examples`**, which is the thing that makes
      the rest of this checkable. A program that keeps count out loud, because
      every other way of watching a swap — a log line, an HTTP response, a
      breakpoint hit — says the new code ran and says nothing about whether the
      old process is still the one running it. A counter that does not go back to
      one does.

      `Greeting.line(int)` is called once a second from `Ticker`, so a swapped
      body has somewhere to land; a body entered once at startup would need the
      restart the feature exists to avoid. Its README walks the three cases: the
      one that works, the one HotSpot refuses, and the one that moves the stack.
      Indexed in the examples README and built by `make java`.

## 7. Watched

- [x] 6.1 `java/hot-swap`, opened as a project: debug **here**, change the
      wording in `Greeting.line`, save. **It works** — the count carries on and
      the wording is the new one:

          BUILD_COMPLETE  Build completed.
          STARTING        Start hot code replacement procedure...
          END             Completed hot code replace
          END             Redefined com.example.hotswap.Greeting

      Four faults stood between the design and that line, and every one of them
      was found by running it rather than by reading:

      1. `updateDebugSettings` wants a JSON string, not an object.
      2. It parses `logLevel` regardless, so a partial settings object NPEs.
      3. `buildWorkspace` wants one too — it had **never run** in this app.
      4. `didSave` was sent for files something *else* wrote and never for a save
         somebody made, so jdtls had nothing to compile.
      5. And `AUTO` is this client's policy: the adapter raises
         `BUILD_COMPLETE` and waits for `redefineClasses`, which nothing sent.

      Two more were mine, in the reporting: `showDebug()` takes the keyboard, so
      every save pulled focus out of the editor and made ⌘Z look broken.
- [ ] 6.2 The same for Gradle, and for a plain Java class with no build file —
      three ways in, one path through jdtls.
- [ ] 6.3 The refusal, deliberately: add a method, and read what comes out. This
      is the message to get right and it cannot be judged from a test.
- [ ] 6.4 A JVM in a pod, over the port-forward this app already opens: a body
      changed and swapped, and a refusal reported with the restart naming what it
      would restart.
- [ ] 6.5 An RCP application attached to with JDWP open, swapped from its build
      output — and the stale case, where the class file is older than the source.

## 7a. What driving it found, that reading could not

- [x] 7a.1 **`vscode.java.updateDebugSettings` wants a JSON string**, the same
      trap `classpathOptions` already records. A dictionary got as far as
      `SEVERE: Parameters for userSettings must be json string:
      {hotCodeReplace=AUTO}` on jdtls's stderr and nothing at all in the app.
- [x] 7a.2 **And it parses `logLevel` regardless.** A settings update that says
      only what it came to say ends in `NullPointerException: Cannot invoke
      "String.length()" because "name" is null` inside `LogUtils.configLogLevel`.
      Carried at `WARNING`.
- [x] 7a.3 **`vscode.java.buildWorkspace` has never run.** It was called with a
      bare `false` and wants a JSON string too, so every call threw
      `ClassCastException: Boolean cannot be cast to String` into a `try?` that
      dropped it — silently, since 0452 put it on the launch path. Encoded, jdtls
      answers a line that had never appeared in this app's log before:

          com.microsoft.java.debug.plugin.internal.Compile compile
          INFO: Time cost for ECJ: 1ms

      **This is load-bearing for the whole feature**: the swap is driven by that
      compile. It is also a bug in the launch path that predates this change, and
      it was found only because hot code replace made somebody read the log after
      a launch.

## 8. Finishing

- [ ] 7.1 Answer the design's remaining open questions with what was found:
      whether a build per save is affordable, whether jdtls imports OSGi bundles,
      and whether "cannot swap at all" is distinguishable from "will not take
      this change" by anything but the text.
- [ ] 7.2 `make test` and `make warnings`, both clean, and their exit codes read
      rather than their output.

No `.abydos/backlog/spec/*.md` file is made untrue: that backlog is gone. What
this changes is `openspec/specs/debug-sessions/spec.md` and
`openspec/specs/language-servers/spec.md`, in the deltas beside this file. The
`language-servers` change is the narrower of the two: that requirement lists what
the debugger's jdtls is asked, and a swap makes it three questions rather than
two.
