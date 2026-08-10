# 437. Typing into a terminal waits behind whatever else the app is doing

Typing into tmux in a pane lags, not always and not predictably. It must not,
whatever else the app has going on — a terminal that answers late is a terminal
nobody trusts, and every other thing this app does is worth less than that.

## It is not the terminal

The input path is already short: `keyDown` encodes and hands the bytes to
`PseudoTerminal.write`, which queues them and drains on a queue of its own.
`InputProbe` splits a keystroke into echo, parse and draw, and there is a
fast path that draws the echo of a key inside a frame.

The lag is in front of all of that. Everything the terminal does — taking the
key, reading the pty, parsing, drawing — happens on the main queue, and so does
everything else in the app. When something else holds that queue, the keystroke
is not slow; it has not been delivered yet. **`InputProbe` cannot see this at
all**, because its stopwatch starts inside `keyDown`, which is already on the
main thread: the wait happens before the first measurement is taken.

## What the stall log says

`StallWatch` has been running unconditionally since launch and writes to
`~/Library/Logs/Abydos/stalls.log`. On this machine, over five days, it had
already caught the answer — 4,455 pings that came back more than 200 ms late:

| what the app said it was doing | stalls | total | median | worst |
|---|---|---|---|---|
| idle (nothing claimed it) | 3712 | 8776 s | 780 ms | 109 s |
| navigator reload | 646 | 858 s | 557 ms | 45 s |
| terminal parse | 74 | 119 s | 517 ms | 49 s |
| tmux tabs | 13 | 60 s | 891 ms | 39 s |
| terminal draw | 10 | 10 s | 958 ms | 2.5 s |

973 of them between one and three seconds, 508 between three and ten, 206 over
ten. On the morning this was written, "navigator reload" was landing every ten
to twenty seconds, 600–1400 ms each, for as long as the log covers.

The 200 ms threshold means everything between one frame and a fifth of a second
is invisible, so this is a floor rather than a measurement.

That table is at the old threshold and nothing later in this entry is
comparable to it. The threshold is 50 ms now, so the log holds far more lines
and the medians in any new reading of it are lower for a reason that has
nothing to do with the app. Compare counts per hour by activity, not to this.

## Steps

The first two rounds are below, done and ticked. The third round is the last
five, and it is a measuring round rather than a fixing one: the one thing this
entry has always owed is a reading taken on a machine that was not being used
by four other agents, and the ranking below says plainly that the suspects left
on it are not clearly worth changing.

- [x] Give the seven suspects names, so a stall in one is not filed as `idle`
- [x] Lower the threshold to where typing is actually felt
- [x] Stop the navigator re-listing the whole project when the window comes forward
- [x] Get the window's directory probe off the main queue
- [x] Stop `LSPClient` writing to a server's stdin on the caller's thread
- [x] Ask the git actor once for the whole tree, not once per row
- [x] Stop the watcher opening the directories it is asking about
- [x] Build a file's text for a language server off the main queue
- [x] One walk of the project to decide what servers it wants, not one per server
- [x] Take the reading this entry asks for, on the quietest window this machine
      offered, and write it in beside the old one
- [x] Say where the quiet window ends, since 0446's agent makes everything after
      it loud, and rotate the log at that boundary
- [x] Make a stall say whether the main thread was *running* during it, since
      `idle` currently means both "busy with something unnamed" and "not
      scheduled at all", and the reading cannot tell them apart
- [x] Make a stall say which process wrote it, since two Abydos on one machine
      share one log file
- [x] Write down what was ruled out this round, and why suspects 4–7 are still
      not the work

No spec delta. Nothing a user can see changed: the threshold, the marks and the
shape of a line in `~/Library/Logs/Abydos/stalls.log` are this project's own
instrumentation, `spec/` has no capability that covers them, and neither of the
first two rounds wrote one either.

## Fixed here

### The navigator re-read the whole project every time the window came forward

`windowDidBecomeKey` calls `navigator.refreshFromDisk()`, which calls
`rootNode.reloadPreservingIdentity()` on the whole tree: every directory the
user has ever expanded, listed again with `contentsOfDirectory`, a `FileNode`
built per entry, and the result sorted with `localizedStandardCompare` — ICU,
per comparison. Nothing unloads, so the cost grows through a session. This
project is a repository with a dozen worktrees inside it: **265,485 entries
under 47,594 directories**.

A directory's modification time moves when an entry is added, removed or
renamed, which is exactly when its listing would come out different, and does
not move when a file's contents change — which the tree does not show anyway.
So `FileNode` now stamps each directory when it reads it and skips the listing
when the stamp has not moved, while still asking each open directory below it.
Measured, in `FileNodeReloadTests`, over 61 directories of 40 files, ten
reloads: **992 ms listing, 5 ms skipping — 199×.**

The stamp is taken with `stat`, not `URL.resourceValues`. Written the obvious
way first, it never worked at all: `NSURL` caches the values it has been asked
for, so every directory came back with its first reading's time and looked
unchanged for ever. Three tests caught it — a file added, a file removed, and a
file added three directories down — and that is why they are worth keeping.

### The window's directory probe ran a tmux client on the main thread

`BottomPanel.scheduleDirectoryCheck` is driven by `TerminalView.onOutput`,
which fires on the echo of every keystroke, and calls `reportWorkingDirectory`
up to four times a second. Under tmux that ran `tmux list-clients` and waited
for it — a fork, an exec and a polled `waitUntilExit`, which `ClaudeHookRunner`
has measured at sixty-odd milliseconds a call — **on the main queue, between a
key being pressed and its letter appearing.** `ProcessPipes.drain` will wait as
long as four seconds when a language server has inherited the write end of the
pipe, which is the case its own note describes.

It now asks on a background queue and reports the answer on the main one.
Nothing about the question needed that queue: two numbers fixed at start-up go
in, and a path comes back.

Only bites with the follow-the-terminal link turned on, which is a setting, so
this is not necessarily the lag that was reported.

### The watcher stopped being anonymous

`handleFilesystemChange` runs on every filesystem event — dozens a minute while
an agent writes files — and did the same kind of work unmarked, so its stalls
were part of the 3,712 recorded as "idle". It is marked "navigator watcher" now.

### The log can see the band that matters, and has names for what is in it

The threshold was 200 ms on the argument that a fifth of a second is where a
person stops believing the keyboard. That is true, and it answers a different
question: 200 ms is where a stall is worth *complaining* about, and this log is
not a complaint, it is the only evidence there is. It is 50 ms now — three
frames at 60 Hz, and comfortably above the noise of a utility-priority thread
being descheduled.

All seven suspects below say their name, so a stall in one of them is no longer
part of "idle": `language sync`, `language server scan`, `navigator git
status`, `document save`, `login shell path`, `diff render`, `debug adapter
stop`.

Two of them had nowhere obvious to put a mark, and the answer is worth
recording. `UserShell.loginPath` is the initialiser of a `static let` and runs
on whichever thread asks first, so there is no call site that is reliably the
guilty one; it is marked inside the work instead. `refreshGitStatus` is
`async`, and a mark cannot span an `await` — the global would then be wrong for
everything that ran in between — so only its two synchronous halves are marked.

And `mark` does nothing off the main thread. There is one name, read when a
*main-queue* ping is late, so a mark taken on a background queue would hang its
label on somebody else's stall. That guard is what lets a mark live inside
shared code — `LanguageServers.suits`, `TextDocument.save`, `UserShell`,
`DAPClient.stop` — which is called from both sides and is only a suspect from
one of them.

### A language server no longer decides when the app may continue

`LSPClient.write` did a blocking `write` to the server's standard input on
whichever thread called it, and the caller was the main one: `didChange` 0.4 s
after a keypress, `didSave` after every auto-save. A pipe write blocks when the
far end is not draining, the far end is somebody else's process, and the 64 KB
the kernel holds is exceeded by one `didChange` of a large file by itself. So a
language server busy re-indexing — or wedged, or stopped — parked the app's
whole event loop, terminal included, until it felt like reading.

**There is no bound on that wait, which is why it needed no measurement.** It
goes to a serial queue per client now: serial because a server's document
notifications are only meaningful in order, per client so that one wedged
server does not hold up the rest, and the worst a stuck server can now do is
make its own queue grow. The `JSONSerialization` of a whole file went with it,
since framing happens on the outbox too.

The test is a hang detector rather than a benchmark, and the margin says so:
`/bin/sleep` never reads its standard input, so it is the server that has
stopped draining; the same call took the whole thirty seconds before and takes
microseconds now, and no amount of load turns one into the other.

**What did not move is the other half of suspect 1** — see below.

### The tree asks git about itself once, not once per row

`refreshGitStatus` awaited the git actor for each node in turn: a few thousand
hops onto the actor and a few thousand continuations resumed back, every one a
block scheduled on the main queue between whatever else is there, on every
watcher event. `statuses(for:)` answers the whole list in one visit, in the
order it was asked.

The git subprocess was never the problem and is untouched — the answers come
from a cache the actor already holds. It was the shape of the loop that put the
work back on the main queue.

Not measured. What is checked instead is the thing a benchmark would not have
caught: that asking together and asking separately give the same answers,
including directory rollups and inherited ignores, and in order.

## Fixed in the round after the first reading

The reading below is what set the order for these. It found the watcher, not
suspect 1, and the watcher is where the second round started.

### The watcher opened the directories it was asking about

`handleFilesystemChange` says it only re-reads directories the user has
expanded, and the guard is right. The lookup in front of it was not.
`FileNode.node(for:)` **lists a directory in order to look inside it** — which
is exactly what revealing a file needs and exactly wrong here — so asking it
about `.build/arm64-apple-macosx/debug/Modules` listed `.build`, then the
configuration directory below it, then the one below that, on the main queue, to
establish that the directory at the end of the path was not open after all.

And the listings stayed. A directory read once is loaded for ever, so every
later reload walked it, `collectPaths` gathered a path for each of its files on
every event, and `applyGitStatus` visited them all. In a checkout with a dozen
worktrees inside it, all being built at once, the tree quietly took on the whole
of that output while nobody was looking at any of it — and each event cost more
than the one before, which is the shape of a stall that gets worse through a
session rather than staying where it is.

`FileNode.loadedNode(for:)` walks only through children that are already loaded
and gives up at the first closed door, which is where the answer already was.
`restoreSelection` uses it too: a path that was selected was on screen, so
everything above it is open, and a path that cannot be reached that way has no
row to select either.

**This is the case the directory-stamp fix could not help with**, and the reason
is worth writing down: the stamp is checked *inside* `reloadPreservingIdentity`,
and none of the work above ever got that far. A build moves the stamps, so the
fix would not have skipped these directories in any case — but it was never
asked to, because the cost was in deciding whether the tree cared at all.

Counted rather than timed, since the machine was not quiet: one event about a
file three directories inside a closed one cost two listings and left both
loaded; it now costs none and leaves nothing.

**Coalescing was considered and refused.** It looks like the obvious answer to a
burst of events and it is not: `FileSystemWatcher` already asks FSEvents for a
0.25 s latency, so the kernel coalesces and a burst arrives at four batches a
second at most. The reading's eight stalls were spread over 26 seconds — about
one every three — so a second coalescer on the main queue would have merged
almost nothing and delayed every file appearing in the tree to do it. The events
were not too many. Each one was too expensive.

### Building a file's text for a language server left the main queue

Suspect 1's remaining half, and it turned out not to be the trade recorded
below. The doubt written down was that the rope is edited on the main thread and
reading it anywhere else is a race. That is true of the **document** — the main
thread reassigns `TextDocument.rope` on every keystroke — and it is not true of
a `Rope`, which is a persistent, `Sendable` value: taking it is a reference bump
and nothing can change it afterwards. `TextDocument.symbols` already hands
exactly that snapshot to the parser's queue, three hundred lines above where the
doubt was written, and `Rope`'s own documentation calls it "a free snapshot".

So there is no trade, no measurement owed, and neither of the two answers the
list proposed is needed. `EditorViewController.withText(of:)` takes the snapshot
on the main queue, decodes the UTF-8 into a `String` on a serial queue of its
own, and sends from the main queue when it is built. Both callers that repeat go
through it — the 0.4 s typing sync and the auto-save that follows every typing
pause. The two that open a file still build it inline, because they happen once.

Serial rather than concurrent, because a `didChange` carries a version number
and a whole file: the older of two arriving last would leave the server
describing text nobody has. And the send is now a moment behind the build, which
it was not before, so it checks the document is still open in a tab first.

### One walk of the project to decide what servers it wants

Suspect 2. `LanguageServers.suits` is a depth-2 directory walk, and `warmUp` and
`serverStatus` both loop over every definition asking it — the same directories
listed, the same names read, once for each of the seven definitions that name
markers. `holdsMarker` made it worse in a smaller way: handed a listing by the
walk above it, it listed the directory again for every `*.ext` marker.

A `DirectoryIndex` lists each directory once and answers both questions from it,
and `suitedDefinitions(in:)` shares one across the loop. Thrown away when the
call returns, deliberately: a project that gains a `go.mod` a minute from now
must be answered from the directory as it is then, and within one call there is
nothing to be stale against.

Counted, since no timing taken on this machine would mean anything: a six
directory project with no manifest in it — the worst case, where every
definition walks all of it before giving up — costs **42 listings one at a time
and 6 together**. The count no longer depends on how many servers this app knows
about, which is the property worth having.

`notice()`'s plain duplicate is gone with it: it asked `suits` for its own
reasons and then called through `suggestion`, which asked again.

The index is asked for hidden entries and filters hidden *directories* out of
the walk by their flag, rather than passing `skipsHiddenFiles` to the listing.
Written the obvious way, jdtls's `.classpath` would have stopped being a marker,
which is what one of the three tests is for — the same shape of mistake as the
`NSURL` caching above, and caught the same way.

## Fixed in the third round, which is the reading and what it asked for

The reading is below. It found `idle` to be not merely most of the stalls but
*all* of them, on a quiet machine, and this entry's own instruction for that
case is "more marks rather than more fixes". These are the two marks, and they
are on the instrument rather than on the app: neither makes anything faster, and
both make the next reading able to say something this one could not.

### A stall now says whether the main thread was running

Every number in this entry has the same hole in it, and the first reading names
it without resolving it: "some of these are starvation rather than the watcher
holding the queue". `StallWatch` pings the main queue and times how long the
answer takes, which is **wall clock**, and a late answer has three causes that
want three different fixes — the main thread running inside unmarked work, the
main thread blocked on something, and the main thread simply not being given a
processor. On a machine at a load average of ten, forty or three hundred and
eighty-six, that last one is not a footnote.

So the watcher now also reads the main thread's own **processor time**, through
`thread_info(THREAD_BASIC_INFO)`, once when the ping goes out and once when it
comes back, and the line carries what fraction of the stall the main thread
spent executing. Reading a thread's counters from outside it needs its Mach
port, and `mach_thread_self()` answers for whoever asks — so the port is taken
on the main thread inside `start()`, which `applicationDidFinishLaunching`
already calls from there, and kept for the life of the process. It is
deliberately never deallocated: the send right is the only handle there is.

**It halves the search rather than ending it, and the proof of that is in the
first line it wrote.** Run with `--stall 800`, which is a `Thread.sleep` on the
main thread, the log says `deliberate stall  cpu 0%` — correctly, because a
sleeping thread executes nothing, and yet that stall is entirely the app's own
doing. So a low fraction means *a wait*, not *somebody else's fault*; blocked
and descheduled still look alike. What it does settle is the other half: a high
fraction is unmarked work, and there is code to go and name.

Verified in the app rather than only in a test, on the debug bundle from this
worktree opened on this worktree — asserted by its window title and by `lsof`
before anything it printed was believed. Two lines, and both are the point:
`272 ms  idle  cpu  24%` during launch, and the deliberate 800 ms at `cpu 0%`.

### A stall now says which process wrote it

There is one log file per machine and there can be more than one Abydos: a
second instance opened beside the first to measure something writes into the
same file, in the same format, with nothing to tell them apart. That is not
hypothetical, it is what happened while taking the reading below, and it cost
the reading it was launched for. The line ends with a pid.

Both fields go on the **end** of the line, after the activity, so that the
summarising command reads a line written before them and a line written after
them the same way — a log outlives the build that wrote it, and a format that
invalidates everything older than the newest change is never readable. That is
what one of the tests is for. The command in this entry has been updated to
take the activity as the first field after the duration, which is a one-word
change and works on both.

## Not fixed, and where to look next

The ranking is kept in its original numbering so that what has gone can be seen
to have gone. What the second round actually did first is not on it at all —
the watcher, which the reading found and the ranking had not.

1. ~~**`LanguageService` `didChange`**~~ — done, both halves. The remaining one
   went off the main queue on the second round, and the reason it was thought
   to be a trade was wrong: the doubt was about the document, not about a
   `Rope` value, which is persistent and safe to hand out. Nothing was traded
   and nothing needed measuring. Neither of the answers proposed here — a
   cheaper snapshot, or incremental `didChange` — was needed, and the note on
   `LSPClient.didChange` refusing incremental still stands.
2. ~~**`LanguageServers.suits()`**~~ — done. One walk for all seven definitions
   that name markers instead of one each, and `notice()`'s duplicate removed.
   Counted at 42 listings against 6, above. The doubt recorded here — that
   `warmUp` and `serverStatus` run at project open and might cost nobody
   anything — was never resolved and did not need to be: the change is smaller
   than the argument about whether to make it.
3. ~~**`refreshGitStatus`**~~ — done, above.
4. **`TextDocument.save`** — `TextDocument.save` serialises the whole rope and
   does an atomic write on the main queue after every typing pause. Everything
   else in that file is on `engineQueue`; this one piece is not. Left rather
   than moved: `save()` `throws`, and every caller reports the error where the
   user asked for the save, so moving it changes what that promise means — and
   an auto-save writing on a background queue beside a manual save on the main
   one is two writers to one file and one `isDirty`. It wants designing, not
   relocating. Marked `document save`.
5. **`UserShell.loginPath`** — a `static let` that runs the user's login shell
   and waits up to five seconds. Warmed on a background queue at launch, but
   whoever asks first while that is still running pays for it on their thread.
   Marked `login shell path`, which is now the only way to know whether the
   warm-up ever actually loses that race.
6. **`DiffView.setDiff`** — `GitPatch.parse` plus two full tree-sitter parses
   inline on the main thread, bounded only at 5,000 lines. Marked
   `diff render`.
7. **`DAPClient.stop`** — busy-waits with `usleep` for up to half a second,
   reached from main-thread actions. Marked `debug adapter stop`.

Four to seven were looked at again on the second round and left where they are,
which is a decision rather than a stopping place. Four wants designing and the
note above says what the design has to answer. Five is already warmed on a
background queue, so the only open question is whether the warm-up ever loses
the race, and that is a question for the log rather than for a change. Six and
seven are both reachable only from something the user just asked for — opening a
diff, stopping a debug session — rather than from between two keystrokes, and
both would want restructuring to move: six needs a generation guard and a
repaint, seven's `terminate`-then-`SIGKILL` wait is load-bearing for the pipe
leak its own comment describes, and unpicking that to save half a second at the
end of a debug session is the wrong trade to make blind. **They are ranked
below the point where a change is clearly right, and the log is what should
promote them.**

### The third round left four to seven alone as well, and now has a reason

Not the same reason. The second round left them because each would want
designing; the third round has a reading, and the reading says something
stronger: **in 119 minutes of quiet session not one of the seven names fired
once.** Not `document save`, not `login shell path`, not `diff render`, not
`debug adapter stop`. They have been marked since the first round and the log
has never once caught them. Changing code that has never appeared in the
evidence is changing code blind, and this entry has already recorded what that
is worth.

And there is a larger reason, which is that **the biggest cause of this app
being busy while somebody types is now known and is not on this list**. 0428,
measuring the app against five hundred bundles, found that opening a Tycho
project burns eight to nine cores indefinitely: `refreshRunConfigurations`
walks the whole project for Java `main` methods on a concurrent queue, with no
coalescing, once per filesystem event. That is **0446**, its own item and its
own agent. Nothing on this ranking is within an order of magnitude of it. The
lesson is the second round's lesson again, arriving from a different direction:
what actually holds the main queue was not on the ranked list either time, and
was found by measuring rather than by reading.

## Ruled out on the third round

- **A driven session of this branch's own build.** Tried, properly: a second
  instance launched on this worktree and asserted before anything it said was
  believed. Abandoned for a reason that had not occurred to anybody — the two
  instances write into one log with nothing to separate them, and the user's
  instance was producing about 0.6 lines a minute the whole time, so every
  count would have been an upper bound of unknown tightness. The pid on the
  line is what that cost bought. The reading is the user's own session instead,
  which is a better session anyway: three and a quarter hours of ordinary use
  against half an hour of a script pretending to type.
- **Building a release app on this branch to measure.** The installed release
  build already carried every change in this entry, and a build at `JOBS=4`
  would have spent the only quiet window this machine had on itself. Measuring
  a debug build was refused for the reason the `Makefile` already gives: an
  unoptimised renderer and terminal emulator are slower to *use*, so its
  numbers would not be about anything in this entry. The debug bundle was built
  and run, but only to check that the new fields appear in a real app.
- **Waiting for the half-hour idle machine the entry asks for.** It does not
  exist and it is not coming: within six minutes of the log being rotated the
  load average went from 9.86 to 163, and the machine has had four agents on it
  all day. Two hours of load-average-ten session, honestly bounded, is the
  reading that was available, and it is a great deal better than the forty and
  three hundred and eighty-six the earlier rounds were taken beside.
- **Sampling the main thread's backtrace when a ping is late.** This is the
  change that would end the search rather than halve it — a stall would arrive
  with the stack that caused it and no mark would ever be needed again. Not
  attempted, and deliberately: it means suspending a thread from a watchdog and
  symbolicating what comes back, which is a real piece of work with a real way
  to go wrong, and the cheap half of the answer — the processor-time fraction —
  has not been *read* yet. If the next reading says the quiet-machine stalls are
  the main thread running, this is the next thing to build. If it says they are
  waits, the answer is somewhere else and this would have been wasted.
- **Coalescing filesystem events.** Not reopened. The second round refused it
  with numbers and the reason has not changed.
- **Moving terminal parsing off the main queue.** Not attempted, again. It is
  the deeper answer below and it is still a piece of work rather than a
  tidy-up.

## What was not measured, and how to measure it

Nothing on either branch was timed, and for the same reason both times: other
agents were working on this machine while it was written — load average 10 to 40
throughout the second round — and a number taken beside that work is worse than
no number, because it is a number somebody will quote.

Every change is right by construction rather than by stopwatch: an unbounded
wait removed, a few thousand main-queue hops replaced by one, directories no
longer listed to find out whether anybody wanted them, a decode moved off the
queue the keyboard shares, and one walk of a project where there were seven.
Where a number was genuinely useful it is a **count** rather than a duration —
2 listings against 0 for a watcher event, 42 against 6 for a project scan —
because a count does not care what else the machine is doing.

The one thing recorded here as needing a before/after no longer does. It was
suspect 1, on the argument that it was a trade; it was not a trade, and the
section above says why.

### The one measurement still worth taking, and the command for it

What is still unmeasured is *how much of the 8,776 seconds all of this was*.
That wants an ordinary session on a quiet machine — no agents, nothing building
— and then a count of the log by activity. Move the old log aside first, since
it holds five days at two different thresholds:

    mv ~/Library/Logs/Abydos/stalls.log ~/Library/Logs/Abydos/stalls-before.log

Then use the app normally for half an hour, with a terminal open and typing in
it, and read what it caught:

    awk -F'ms  ' 'NF>1 {split($1,a," "); split($2,b,"  "); k=b[1];
      n[k]++; s[k]+=a[2]; if (a[2]+0>w[k]+0) w[k]=a[2]}
      END {for (k in n) printf "%5d  %8.1f s  %6d ms worst  %s\n",
      n[k], s[k]/1000, w[k], k}' ~/Library/Logs/Abydos/stalls.log | sort -rn

`idle` falling and the seven names appearing is the whole result. If `idle` is
still most of it, the sweep missed something and the next step is more marks
rather than more fixes. If `navigator watcher` is small while files are being
written into the project, the change above is what did it — and if it is not,
the next place to look is the diff between an event that lands on an open
directory and one that does not.

The third round added two fields to the end of a line, so this command takes
the activity as the first thing after the duration rather than the whole rest
of the line. Written that way it reads a line from before those fields and a
line from after them the same way, and the whole log stays summarisable across
a rebuild. And since the third round found `idle` to be *all* of it, the
second command is now the one that matters — it splits `idle` into the two
things it has always meant:

    awk -F'cpu ' 'NF>1 {c=$2+0; b=(c<25?"main thread not executing":
      (c<75?"partly":"main thread running")); n[b]++}
      END {for (k in n) printf "%5d  %s\n", n[k], k}'
      ~/Library/Logs/Abydos/stalls.log | sort -rn

A stall where the main thread ran the whole time is unmarked work, and the next
thing to give a name to. A stall where it barely ran is a *wait*, and the two
kinds of wait — descheduled by a busy machine, or blocked on something this
program chose to wait for — still look the same. See the caveat under the
change itself; it halves the search rather than ending it.

**This measurement has now been taken** — see "Second reading" below — as far as
this machine allowed, which was not as far as the paragraph above wanted.

### What the third round still could not measure

- **The half hour of idle machine.** It did not happen and it is not going to
  happen here; the section on what was ruled out says why, and the reading says
  what was taken instead.
- **What the load average was for most of the measured window.** It was recorded
  at the end (9.86 at the moment the log was rotated, 9.48–13.69 across the
  three averages half an hour before that) and not at the start, because nobody
  knew at the time that the window would turn out to be the measurement. The
  session is known to be bimodal from its own timestamps; whether the loud
  stretch was the app or the machine is not known, which is exactly the hole the
  processor-time field was added to close.
- **Whether the thirteen quiet-stretch stalls were work or waiting.** The
  instrument to answer that now exists and did not exist when they were caught.
  No reading has been taken with it — the machine went to a load average of 163
  six minutes after the window closed — and every number in this entry predates
  it. This is the first thing the next round should do, and it costs nothing but
  an hour of ordinary use.
- **Any before/after of the four changes in the first two rounds.** Still not
  possible without keeping a build of the old code around to run beside the new
  one, and the argument in this section for why that was never worth doing has
  not changed.

## The deeper answer, still not attempted

The terminal does not need to share a queue with the project. Parsing runs on
main because the emulator and the renderer both live there, and moving it is a
real piece of work rather than a tidy-up. Everything above makes the queue
shorter; this is the one that stops the terminal caring how long it is.

## First reading from the lowered threshold, on a real session

Taken the way this entry asks for it — an ordinary session, counted by activity —
on a build carrying both halves of the work, over the first six minutes after a
restart:

| activity | stalls | range |
|---|---|---|
| navigator watcher | 8 | 57–423 ms |
| idle | 6 | 99–576 ms |

**Four of those eight would not have been recorded at all at the old 200 ms**,
which is the threshold change paying for itself immediately: 57, 61, 72 and 99 ms
are invisible in every number at the top of this entry.

The eight are one 26-second cluster, and what was happening during it is known —
two agents were writing files into the repository. So a build, or anything else
writing to the project, still puts the navigator watcher on the main queue often
enough to be felt, *after* the directory-stamp fix that made a reload 199× cheaper
when nothing moved. That fix skips directories whose stamp has not moved; a build
moves them, so it is the case the fix cannot help with.

**Honest caveat, and it is a large one.** The machine was at a load average of
around 40 during that window, from the same agents. Under that, everything is
late and some of these are starvation rather than the watcher holding the queue.
What the reading establishes is *where to look next* and that the instrumentation
works — not how much the watcher costs on a quiet machine. That number still
wants an idle session, and the command for it is above.

### What the reading led to

It was better evidence than the ranking, and it was right to follow it. The
ranking had `LanguageServers.suits` second and the watcher nowhere, because the
watcher had only just stopped being anonymous; one reading with a name on it
moved it to the front. Following it found something no amount of ranking would
have: the expensive part of a watcher event was not re-reading the directories
somebody had open, it was deciding whether any of them were — and that decision
opened them.

The lesson worth keeping is the one about the mark rather than the one about the
bug. `handleFilesystemChange` had been doing this for as long as it has existed,
its cost was recorded as `idle` for five days, and nothing in the first round's
analysis found it. It took a name and one honest reading.

## Second reading, on the quietest machine this has had

The reading this entry has owed since it was written. It is **not** the half
hour of idle machine asked for above — that window did not exist and it is not
going to; see the boundary below. It is the next best thing, and better than it
sounds: three and a quarter hours of an ordinary session, on a release build
carrying every change in this entry, on a machine at a load average of about ten
rather than the forty and the three hundred and eighty-six the earlier rounds
were taken beside.

**What was measured.** The app the user was already running — installed release,
built 11:55Z from a tree carrying all of the above — from its launch at
**12:02:14Z** to **15:15:52Z**, the last line before the log was rotated. Ten
cores, a Mac13,1. Every duration below is **wall clock**: `StallWatch` measures
how long a ping took to come back, not processor time. The load averages are
runnable-thread counts, and the one CPU figure quoted is processor time and says
so.

| activity | stalls | total | worst |
|---|---|---|---|
| idle | 94 | 91.4 s | 22811 ms |
| terminal parse | 6 | 3.9 s | 2286 ms |
| navigator watcher | 3 | 11.3 s | 5050 ms |
| tmux tabs | 1 | 0.4 s | 372 ms |

**Per hour, which is the only comparison worth making.** 3.227 hours, so 29.1
`idle`, 1.9 `terminal parse`, 0.9 `navigator watcher`, 0.3 `tmux tabs` — 32.2
stalls an hour at 50 ms. Ninety-two of the hundred and four were over 200 ms, so
the directly comparable figure is **28.5 an hour against the old table's 37.1**,
and that old figure is a floor: 4,455 over "five days" assumes the app was up
for all of them and it was not.

**`navigator reload` is gone. Zero, in three and a quarter hours, against 5.4 an
hour before.** That is the directory stamp, and it is the one line in this table
that is unambiguously a change in this entry doing what it was written to do —
`windowDidBecomeKey` fires whenever the window comes forward, which happened
many times in that window, and it no longer costs anything.

**The rest of the table is honest but weak evidence.** `terminal parse` went
*up* per hour (1.9 against 0.62) and `navigator watcher` did not exist as a name
before, so neither can be compared to anything. Nothing in this entry touched
terminal parsing, and the deeper answer above is still not attempted.

### The two-hour quiet stretch inside it, which is the real result

The session is not uniform. Split by ten-minute bucket it is plainly bimodal:
thirty-nine stalls in the first half hour after launch, forty in a 13:50–14:30
burst carrying 75 of the 91 seconds, and almost nothing in the two stretches
either side. Take the two calm stretches on their own — **12:30–13:45Z and
14:32–15:16Z, 119 minutes** — and the whole of what the log caught is:

    13 stalls, 3.0 s in total, worst 502 ms — every one of them `idle`

**6.6 stalls an hour, 1.5 seconds of stall per hour, and not one of the seven
names fired.** Not `navigator watcher`, not `language sync`, not `document
save`, not `login shell path`, not `diff render`, not `language server scan`,
not `debug adapter stop`. On a machine that is merely busy rather than
overloaded, an Abydos with a project open and a terminal in it is close to
silent, and every remaining stall is unattributed.

That is the answer to the question this entry asked, and it is the answer that
was least expected: **`idle` is not most of it, `idle` is all of it.** The
entry's own instruction for this case — "the next step is more marks rather than
more fixes" — is what the third round then did, and the mark it added is below.

### What this reading cannot say, and what was done about it

Thirteen stalls of 79–502 ms with no name on them are one of three completely
different things, and the log as it stood could not tell them apart:

- the main thread was **running**, inside work nobody has marked;
- the main thread was **blocked** — a pipe write nobody was draining, a lock, a
  subprocess being waited on, which is exactly the shape of the worst bug this
  entry found; or
- the main thread was **not scheduled**, because ten cores were busy with
  something that is not this app at all.

At a load average of ten on ten cores the third is not a remote possibility,
it is the base case, and the same doubt is written into the first reading above
("some of these are starvation rather than the watcher holding the queue") where
it was left unresolved. It sits under every number in this entry, including the
22.8-second `idle` in the table, which is not credibly a main thread *doing*
anything for 22.8 seconds.

So the third round made a stall say which it was. See "A stall now says whether
the main thread was running" below. Every reading in this entry predates it and
none of them can be re-derived; the next one will not have the doubt.

### Where the quiet ends

**15:16Z.** The log was moved to `~/Library/Logs/Abydos/stalls-before-0437.log`
at that moment, at a load average of 9.86, and everything above is from that
file. Immediately afterwards another agent started on **0446** — the Tycho spin
0428 found — whose first move is to reproduce a fault that burns eight to nine
cores, with an Abydos build of its own writing into the same `stalls.log`. Six
minutes later the machine was at a load average of **163**, and at the time of
writing 26. Nothing logged after 15:16Z belongs in this entry, and a reading
taken across that boundary would be worthless.

The four lines that landed in the new `stalls.log` between 15:17Z and 15:22Z are
from this round's own guarded launch and from the user's instance, and are noted
here so they are not mistaken for a session: 252 ms `terminal draw`, then three
`idle` of 107, 174 and 99 ms.

### Two Abydos, one log

Taking this cost most of an hour to something worth writing down. A second
instance was launched on this worktree to drive a session with typing in it —
asserted, before believing anything, by its window title and by `lsof` showing
the worktree open under its pid — and the moment it was up it became obvious
that its stalls and the user's instance's stalls go into the same file, in the
same format, with nothing to tell them apart. The user's instance was not idle:
it had been writing about 0.6 lines a minute all afternoon. There is no reading
to be had from a shared log, so the instance was quit, the *user's* session was
used as the measurement, and the log line grew a pid. That is the second change
below.

### The terminal in the measured session was real, and it was worth checking

A `TMUX_TMPDIR` left behind by an agent killed the day before was still in the
tmux server's global environment and therefore in every shell descended from it:

    TMUX_TMPDIR=…/scratchpad/t0404/tmuxdir

Abydos takes it from whatever launched it and hands it to the tmux it starts, and
the socket path that comes out is about 140 characters against macOS's ~104, so
the terminal dies immediately with `error connecting to … (File name too long)`.
An app launched from a poisoned shell has a terminal panel that is not a terminal
— no pty, no tmux, none of the work the panel normally does — and a stall reading
taken there would be measuring an app with its noisiest component switched off.

**It did not touch the reading, and this is the evidence rather than the
assumption.** The measured session is the user's own instance, which was not
launched from any of this round's shells and has no `TMUX_TMPDIR` in its
environment at all. Its tmux client started at 14:02:15 local — the same second
the app did, the first second of the window — and was still alive with a
connected socket three and a half hours later, and a login shell of its own
appeared under it at 16:45, inside the window. The window's own stall lines agree:
six `terminal parse` and one `tmux tabs` are not things a dead panel produces.

Of this round's two launches, neither contributed a number. The first was quit
before it measured anything and its four log lines are listed above as excluded;
the second was the `--stall 800` check of the new fields, which never opens a
terminal at all.

**Worth an entry line even though it did not bite:** the app passes
`TMUX_TMPDIR` through unexamined, and a value that cannot produce a usable
socket path is one it could reasonably refuse — it knows the length limit and it
knows what it is about to build. That is the same shape as the leaked `$TMUX`
0440 already strips from panes. It is an observation, not work for this branch:
0437 is about *how long* the terminal takes to answer, and this is about the
terminal not existing.

---

Numbered after 0436, which is where the list had got to on the main working
tree — this was written on a branch that started before 0435 and 0436 existed,
and first took 0435. By the ordering in the README a bug that stops somebody
working belongs above everything currently open.

0435 is the PlantUML test that fails only when the suite is busy, which turned
up here too: three full runs on this branch failed in PlantUMLServerLiveTests,
MermaidLiveTests and SilentRuntimeTests, all of them timing-sensitive, all of
them green on their own and green again on a warm build.

The second round says the same thing louder, and it is worth writing down as
evidence for 0435 rather than as an excuse. One full run before merging main was
green: 1,997 tests, at a load average of about 30. Two runs after it were not —
one red in DevContainerLiveTests, then four red in StreamedOutputTests,
LSPHandshakeOrderTests, PseudoTerminalTests and SilentRuntimeTests — taken while
the machine was at a **load average of 386**. Every one of them is an assertion
about a deadline: 1.7 s against a 1 s bound, 30.8 s against 10. All five passed
on their own straight afterwards, and the same run printed
`PERF 10k lookups (2k lines) 9873.75 ms` for a benchmark that has no business
taking ten seconds. Nothing in this entry's changes is anywhere near any of
them. **The suite has no way to say "I could not be run", so it says "you broke
it" instead**, and that is the fault 0435 describes.

The third round is the cleanest example yet, because both halves were run within
four minutes of each other and only the machine changed. A full run at a load
average that went from 25 to 176 during it came back red in exactly two places,
both `…LiveTests` and both a deadline: `DevContainerLiveTests` waiting for a
container to be gone, and `JavaLiveTests` timing out on `workspace/executeCommand`
after 49 seconds. Re-run on their own, at a load average of 148, **the same
jdtls test passed in 7.1 seconds** — a seventh of the time it had just spent
failing to finish. The whole suite then passed, 2,166 tests in 326 suites in
30.5 seconds, as the load fell from 97 to 55.

There is a joke in the second failure that is worth writing down: the agent
loading the machine was the one working 0446, whose whole job is to reproduce
jdtls opening a Java project. `JavaLiveTests` did not fail because of anything on
this branch; it failed because somebody else was already using the thing it
tests.
