# 452. jdtls hosts the debugger even when another server edits

0449 lets a project choose its Java server and 0450 measured why somebody would:
on a 143-bundle project jdtls was still silent at 601 seconds where kmp-lsp
answered in 2.6. But choosing kmp-lsp today costs the debugger entirely, because
**java-debug is an Eclipse bundle loaded inside jdtls** — `DebugAdapters.java`
says so, and `LanguageServers.swift` passes it as the `bundles` option under
`guard definition.setup == .java`. No jdtls, no adapter, no debugging.

That is a bad trade to have to make. The fast server is wanted for editing five
hundred bundles; the debugger is wanted a few times a day. Nothing about those
two facts requires choosing between them.

## This is not what 0449 ruled out

0449 rejected two servers for one language, and the reason was specific: two sets
of diagnostics over one file with no rule for which wins. **These two have
disjoint jobs.** kmp-lsp answers about files; jdtls, in this arrangement, answers
about nothing at all and exists to host an adapter. Nobody has to decide which
completion is right, because only one of them is asked.

Whoever picks this up should not cite 0449 as a reason not to — but should make
the disjointness real in the code rather than in a comment, because a second
Java server that starts answering `textDocument/*` is exactly the mess 0449
refused.

## The cost, which is the whole design question

jdtls's expense is not its startup, it is **importing the project** — resolving
the classpath from the poms, which on a Tycho reactor is minutes and gigabytes.
And the adapter needs that import: it launches a class with a classpath, and the
classpath is what the import computes.

So "start jdtls only for debugging" means paying the import when somebody presses
Debug. Three ways, and they are not equally good:

- **On first debug.** Honest and slow: the first Debug of a session waits for an
  import it cannot skip. It must say what it is waiting for — a spinner that
  looks like the debugger hanging is worse than the wait.
- **When the project opens, in the background.** Debug is instant and the machine
  pays the whole import for a session that may never debug — which is most of
  them, and is the cost 0450 was trying to escape.
- **Neither: get the classpath elsewhere.** `mvn dependency:build-classpath` and
  `mvn help:evaluate` can answer without jdtls at all, and a launch needs a
  classpath and a main class rather than a language server. That is a different
  and possibly much better design, and it is the one worth an hour of thought
  before writing any of the above. It would also mean Gradle needs its own
  answer, and Tycho likely needs jdtls regardless, since a p2-resolved classpath
  is not something Maven prints.

Measure before choosing. 0450 left `--report-answer` and `Scripts/scale.sh`
behind and the corpus is cloned; how long an import takes before the *adapter*
can launch something is a number nobody has taken, and it may be far shorter than
the ten minutes completion needed.

## Worth knowing

- `JavaTooling.debugPlugin()` finds the bundle, overridable with
  `ABYDOS_JAVA_DEBUG_PLUGIN`, and `!inContainer` guards it — a devcontainer's
  jdtls is given no bundle at all, so debugging in a container is already absent
  and this item should not pretend otherwise.
- `DebugAdapters.for(...)` picks Java by finding a build file, not by asking
  which server is running, so it will already offer to debug a project whose
  editing server is kmp-lsp — and today that offer cannot be honoured. Whatever
  else changes, that lie should stop.

---

## What the measurements said

**Conditions, and they were bad ones.** A ten-core machine with two other agents
building on it throughout: the load average under these readings ran between 12
and 55, peaking at 138 mid-run, where 0450's comparable runs were taken at 12.6
and 30.8. Every figure below carries the load it was taken at, and the
cross-project comparisons to 0450 should be read as this machine being three to
four times busier than it was that day. What the readings are *for* — the distance
between two answers from the same server on the same run — is unaffected by that,
which is why the debugger's two questions were added to the same loop rather than
timed on an afternoon of their own.

The app was built with a bundle id of its own, so it had empty settings, no
project naming an image, and `/opt/homebrew/bin/jdtls` 1.60.0 is what ran. Both
corpora were APFS clones under a scratch directory, never the checkouts
`Scripts/corpus.sh` maintains. Another agent was running its own scale runs
against those checkouts at the same time; `Scripts/scale.sh` samples only its own
app's children, which 0428 built it for, and it held.

### The two questions, three runs

| | Platform, 143 bundles, cold | Sirius, 106 bundles, cold | Sirius, warm workspace |
|---|---|---|---|
| **debug adapter listening** | **≤ 50.6 s**, see below | **36.9 s** | **10.4 s** |
| outline of the open file | 50.6 s (410 symbols) | 39.3 s (17 symbols) | 8.2 s |
| completion | **still silent at 661 s** | 39.3 s | 8.2 s |
| go-to-definition | **still silent at 661 s** | 39.3 s, another bundle | 8.2 s |
| **debug classpath** | **still silent at 661 s** | still silent at 280 s | **answered at 10.4 s, empty** |
| jdtls resident at the end | 3.64 GB, 3 m 32 s cpu | 3.46 GB, 2 m 20 s cpu | |
| load at the readings | 19–20 (1.9–2.0/core) | 41–45 (4.1–4.5/core) | 33–35 (3.3–3.5/core) |

The third run is the same Sirius clone a second time, so jdtls found the Eclipse
workspace its first run left and everything is four times faster. It is not
comparable to the second for *timing* and it was not taken for timing: it was
taken to find out what the classpath answer actually is, and it is the run that
found it.

**The Platform figure for the adapter is an upper bound and the reason the harness
changed.** The first run asked all five questions in one round, and a round is as
slow as the slowest question in it — `completion` was timing out at thirty seconds
a go. So the adapter was reported five milliseconds after the outline, which is the
shape of a number bounded by its neighbours rather than measured. jdtls's own log
settles it anyway: `JavaDebuggerServerPlugin.start` is logged at the moment the
command is first invoked, so the plugin activates *on being asked*. The two
questions now run in a loop of their own, which is what the later runs used — and
in the third the adapter answered 2.2 seconds *after* the file questions, so what
bounds it is the round rather than the server.

### What that means, and it is not what the entry guessed

The entry hoped the adapter would need far less than the ten minutes completion
needed. **Half of it does and half of it does not, and the half that matters is
the classpath.**

- **The port is nearly free.** java-debug is lazily activated: it is listening the
  first time it is asked, without the project being imported at all. On the cold
  Sirius run it answered 2.4 seconds *before* the outline did.
- **The classpath is the import.** `java.project.getClasspaths` cannot answer until
  jdtls has resolved the project, which is the same wall completion is behind. On
  `eclipse.platform.ui` it was still silent at eleven minutes, with jdtls holding
  3.64 GB at 0% processor and never saying it had failed — the state 0450 found and
  called the worst shape a wait can have.
- **And on a Tycho bundle the answer, when it comes, is empty.** The warm Sirius
  run got `getClasspaths` answered at 10.4 s **with nothing in it**, in the same
  round the adapter came up, on a project where completion and go-to-definition
  were working. Not a wait: an answer. `plugins/org.eclipse.sirius/pom.xml` is 27
  lines of `<packaging>eclipse-plugin</packaging>` with no `<dependency>` in it,
  and the classpath it needs is 112 lines of `Require-Bundle` in its
  `MANIFEST.MF`, resolved against a p2 target platform. There is nothing for jdtls
  to report and it reports nothing.

So the honest account of what pressing Debug costs is: **nothing beyond what that
project's jdtls costs anyway**, and on a Tycho bundle what it costs is not enough,
because no classpath exists to be had. That was true before this item too — with
jdtls chosen for editing, the same command gave the same empty answer, and the app
sent the launch anyway and the JVM died with `ClassNotFoundException` on the class
somebody had asked for. This item does not make Tycho debuggable. What it does is
stop the *choice of editing server* deciding whether anybody can debug, and turn
that empty answer into a sentence.

## Where the classpath comes from, and why

**From jdtls's import, started when somebody presses Debug.** The first of the
three, and the entry asked for an hour on the third before writing any of it.
Here is the hour.

### The adapter is not a classpath problem

`mvn dependency:build-classpath` prints a classpath. It does not print a
*debugger*. java-debug is `com.microsoft.java.debug.plugin`, an Eclipse bundle
whose entry point is a jdtls command handler — there is no standalone launcher
for it, and the DAP server it starts is reached by asking the language server
`vscode.java.startDebugSession`. So the third design does not remove jdtls from
the picture; it removes the *import* from the picture and keeps the server.

Worth knowing, and it is what the measurement showed: **the port is the cheap
half.** `JavaDebuggerServerPlugin.start` appears in the log at the moment the
command is first invoked, not at startup — the bundle is lazily activated and
answers on demand, without the project being imported at all. Everything
expensive is on the other side of it.

### Where it would break, and it is exactly the project this is for

Even with a classpath from Maven, java-debug still resolves a breakpoint's source
path to a fully qualified class name through JDT's model of the workspace. A
session against a workspace nothing imported starts the JVM and binds no
breakpoints — a debugger that runs your program straight through, which is worse
than a slow one.

And Maven cannot answer for a Tycho reactor, which is measured rather than
argued. In the Sirius corpus, **93 of 98 bundle poms name no `<dependency>` at
all** and 94 are `<packaging>eclipse-plugin</packaging>`:
`plugins/org.eclipse.sirius/pom.xml` is 27 lines and declares nothing, while its
`META-INF/MANIFEST.MF` is 112 lines of `Require-Bundle` and `Import-Package`
resolved against a p2 target platform. `dependency:build-classpath` on that
module prints an empty classpath, correctly — the dependencies were never in the
pom. The design that avoids jdtls fails on the shape of project the whole line of
items 0446, 0449 and 0450 exists for, and would need a second answer for Gradle
on top.

So the classpath stays where the build knows it, and this item is about *when*
that is paid rather than by whom.

### Between "on first debug" and "in the background at project open"

On first debug. The background import is the cost 0450 measured its way out of:
somebody chooses the fast server on a five-hundred-bundle product precisely so
that opening it does not cost a JVM and four gigabytes, and paying that at every
project open — for the great majority of sessions, which never debug — hands the
cost straight back. It is also the worse failure when it goes wrong: an import
nobody asked for, eating cores in the background, with nothing on screen that
explains it.

Pressing Debug is a moment when a person is expecting to wait, and it is the one
moment the wait can be *explained*. So it says what it is waiting for, in jdtls's
own words where it has any — `language/status` is read for the first time here,
and it is the only place the server says which minute of the import it is in.

## How the disjointness is enforced rather than described

The entry asked for this specifically, so here is what a reader can go and check.

- **`JavaDebugHost` owns its `LSPClient` privately and hands it to nobody.** The
  type's whole surface is `startDebugSession`, `classpath(for:)`,
  `waitUntilLaunchable`, `stop` and `isRunning`. There is no way to spell
  `textDocument/didOpen` at it from outside that file, so routing a document to it
  is a compile error rather than a mistake somebody makes at four in the
  afternoon.
- **It is not in `LanguageService.servers`.** That table is what `opened`,
  `changed`, `closed` and every question are routed through — and
  `workspaceSymbols` fans out over *every* key with the project's prefix, so an
  entry in there really would be a second answer to one question. Debug hosts live
  in a table of their own, reachable only by asking for the debugger.
- **The diagnostics it is sent are counted and dropped.** jdtls publishes
  compilation problems for everything it imports whether anybody asked or not, and
  those are precisely the two-sets-of-diagnostics 0449 refused. The host's
  callback increments `diagnosticsDropped` and does nothing else, which makes the
  drop a number a test can read rather than an absence that proves nothing.
- **Its Eclipse workspace is not the editing server's.** Two jdtls in one `-data`
  directory corrupt it. They cannot both run for one project by construction, and
  the separate directory is what keeps that true if somebody changes the choice
  while a session is up — at which point the debugger's one is stopped, because
  what it holds is then a gigabyte of nothing.

## Ruled out

**Getting the classpath from Maven** — the third design, and the section above is
the hour the entry asked for. Three reasons, in the order they became decisive:
java-debug is a jdtls bundle, so Maven buys the classpath and not the *debugger*;
breakpoints are bound by resolving a source path to a class name through JDT's
model, so a session over a workspace nothing imported would run the program
straight through; and **93 of 98 Sirius bundle poms declare no `<dependency>` at
all**, so `dependency:build-classpath` prints an empty classpath for exactly the
projects this was for.

**Importing in the background when the project opens.** Instant debugging paid for
by every session that never debugs, which is most of them, and it is the cost 0450
measured its way out of. Also the worse failure: cores eaten by something nobody
asked for, with nothing on screen accounting for it.

**A standalone java-debug, without a language server at all.**
`com.microsoft.java.debug.plugin` has no launcher — its entry point is a jdtls
command handler. The `.core` half is a plain jar, but what turns it into a DAP
server is the Eclipse wiring, and reimplementing that is writing a Java debugger.

**Putting the debug host in `LanguageService.servers` with a flag saying not to
ask it things.** It would have been four lines instead of a type, and the four
lines are a promise. `workspaceSymbols` alone would have broken it: it walks every
key under the project and asks each server. A flag is something the next person
has to know about; a private client is something they cannot get past.

**Sharing the editing server's `-data` directory**, which would have saved an
import for anybody who later switches to jdtls for editing. Two jdtls in one
Eclipse workspace is corruption, and the saving is one import against a class of
bug nobody would diagnose from the symptom.

**Following the project into its devcontainer.** A project worked on in there
still has no Java debugger. The bundle is a path out here and the JVM would be
this machine's, so what got debugged would be a different toolchain from the one
the code was compiled with — the fault the first requirement in
`spec/language-servers.md` exists to prevent. It was already absent, via the
`!inContainer` guard on the bundle; what changed is that it now says so instead of
failing obscurely.

**Reusing `startJavaDebugAdapter`'s retry loop for the wait.** Five attempts two
seconds apart is right for a jdtls that has already imported and is a moment
behind; it is nothing like a Tycho import. The editing-server path keeps it, and
the host has a wait of its own that reports progress.

**Making `RunConfiguration.isDebuggable` consult the machine.** It is a pure value
about a configuration — does it name a class to start — and asking it whether
jdtls is installed would put a `PATH` walk and a directory scan inside a property
the run list maps over. The question "can this project debug Java at all" is asked
where Debug is offered, once, and is answered by `JavaDebugHost.refusal`.

**Fixing jdtls's Tycho import**, which is what the `eclipse.platform.ui` reading is
really about. It is not this item and it may not be anybody's: jdtls goes quiet at
3.6 GB, having written Eclipse metadata into the project, and never says it
failed. Worth its own entry.

## What surprised, and what cost time

**The port is free and the classpath is everything.** The entry's hope was that
the adapter would need much less than completion did. The port needs nothing at
all — java-debug is lazily activated and answers the first time it is asked,
before any import — and the classpath needs the whole import. So the item's
premise was half right, and the half that was wrong is the half a launch cannot do
without.

**jdtls answers `getClasspaths` for a Tycho bundle promptly, and with nothing in
it.** Not a wait — an answer. Found by staring at a run where completion answered
at 39 s and the classpath line never appeared, and then at
`plugins/org.eclipse.sirius/pom.xml`: 27 lines, `<packaging>eclipse-plugin</packaging>`,
no dependencies, beside a `MANIFEST.MF` of 112 lines of `Require-Bundle`. The old
code turned that into a launch request with an empty `classPaths` and a JVM that
died with `ClassNotFoundException` on the class somebody had asked for — a
misleading failure that predates this item and is now a sentence. The `?? 0` that
flattened "did not answer" and "answered emptily" into one number is what made it
take an hour, and both the probe and the product code now keep them apart.

**`Scripts/scale.sh`'s project guard was broken for anything under `/tmp`.** A
scratch clone is reached as `/private/tmp/...` and reported by the app as
`/tmp/...`, because `standardizingPath` strips `/private` as a documented special
case. So the guard failed on a run whose window was on exactly the right project
— the worse of the two ways for a guard to be wrong, since a guard nobody believes
is a guard nobody reads. Fixed by comparing both sides with `/private` off.

**The scratchpad is shared between agents.** `run1.log` was overwritten mid-item
by another agent's scale run on 0470, which is why the numbers above are recorded
here rather than cited to a file. Later files are prefixed with the item number.

**`ContainerLSPLiveTests`'s leak, seen.** The app's own sweep printed `Removed 4
container(s) left by an earlier run: abydos-lsp-jdtls-65883-6, …-57863-23,
…-52074-23, …-67876-23`. Cleaned up by the app rather than by hand, and not
touched here — it is still the leak 0427's note describes.

## Estimate

2026-08-11 16:00 — about two hours left, a second measurement running

## Steps

- [x] A way to ask the question at all: `--report-answer` polls the three
      questions an editor asks, and neither of the debugger's two could be asked
      — added, beside them, on their own clock
- [x] Measure how long jdtls needs before the *adapter* can launch, as against
      before completion answers — the two may be very different. They are: the
      port is free and the classpath is the whole import
- [x] Decide where the classpath comes from, and write down why: jdtls's import,
      or Maven directly
- [x] `Scripts/scale.sh`'s own project guard, which failed on every project under
      `/tmp` and so on every scratch clone of the corpus
- [x] Tell "the server did not answer" apart from "the server answered with an
      empty classpath", which the old code could not and a JVM died of
- [x] A second Java server that hosts the adapter and answers nothing about
      files, enforced rather than described
- [x] Tell a classpath *about this project* apart from the one jdtls answers with
      before it has imported anything, which is a well-formed answer for its own
      fallback workspace
- [x] Compile before launching, because a classpath is a set of directories and
      jdtls fills them after the import
- [x] Debug offered only when it can actually be honoured
- [x] Say, where somebody chooses a server, what it costs them — 0449 already
      shows the choice; this is the sentence beside it
- [x] `--dump-settings --with-help`, because that sentence is only in the help and
      the dump printed titles alone
- [x] Driven for real: a project whose editing server is not jdtls, debugged from
      cold, and the row it leaves in Running Servers
- [ ] Write down here what was ruled out on the way
- [ ] `spec/language-servers.md` says what the project now does
