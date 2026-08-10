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

    awk -F'ms  ' 'NF>1 {split($1,a," "); n[$2]++; s[$2]+=a[2];
      if (a[2]+0>w[$2]+0) w[$2]=a[2]}
      END {for (k in n) printf "%5d  %8.1f s  %6d ms worst  %s\n",
      n[k], s[k]/1000, w[k], k}' ~/Library/Logs/Abydos/stalls.log | sort -rn

`idle` falling and the seven names appearing is the whole result. If `idle` is
still most of it, the sweep missed something and the next step is more marks
rather than more fixes. If `navigator watcher` is small while files are being
written into the project, the change above is what did it — and if it is not,
the next place to look is the diff between an event that lands on an open
directory and one that does not.

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

---

Numbered after 0436, which is where the list had got to on the main working
tree — this was written on a branch that started before 0435 and 0436 existed,
and first took 0435. By the ordering in the README a bug that stops somebody
working belongs above everything currently open.

0435 is the PlantUML test that fails only when the suite is busy, which turned
up here too: three full runs on this branch failed in PlantUMLServerLiveTests,
MermaidLiveTests and SilentRuntimeTests, all of them timing-sensitive, all of
them green on their own and green again on a warm build.
