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

## Not fixed, and where to look next

Ranked as before, with the two that were done struck through and what remains
of them kept where it belongs:

1. ~~**`LanguageService` `didChange`**~~ — half of it. The blocking write and
   the JSON are off the main thread. **Building the entire file as a `String`
   from the rope still happens on the main thread**, at
   `EditorViewController.scheduleLanguageSync`, every 0.4 s of typing and on
   every auto-save. It cannot simply be moved: the rope is edited on the main
   thread and reading it from anywhere else is a race. The honest answers are a
   snapshot the rope can hand out cheaply, or incremental `didChange` — and the
   note on `LSPClient.didChange` says why incremental was refused, which is
   still a good reason. Marked `language sync`, so the log can say whether it
   is worth either.
2. **`LanguageServers.suits()`** — a depth-2 directory walk per server
   definition, in a loop over every definition, from three `@MainActor`
   callers. Still true, and **deliberately left**: the walk is identical for
   all ten definitions, so a bulk `suitedDefinitions(in:)` that lists each
   directory once would cut the I/O roughly tenfold — but the callers that
   loop are `warmUp` and `serverStatus`, which run at project open rather than
   between keystrokes, and nothing here knows yet whether that costs anybody
   anything. `notice()` walks twice for one file, once itself and once inside
   `suggestion`, which is a plain duplicate and the cheapest thing to remove
   first. Marked `language server scan`; the log decides.
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

## What was not measured, and how to measure it

Nothing on this branch was timed. Another agent was taking performance
baselines on the same machine while it was written, and a number taken beside
that work is worse than no number: it is a number somebody will quote.

Both changes here are right by construction rather than by stopwatch — an
unbounded wait removed, and a few thousand main-queue hops replaced by one —
so neither claim rests on a measurement. What is genuinely unmeasured is *how
much of the 8,776 seconds they were*, and that is now answerable without a
stopwatch at all: run the app for an ordinary session on a quiet machine and
count `~/Library/Logs/Abydos/stalls.log` by activity. `idle` falling and the
seven names appearing is the whole result; if `idle` is still most of it, the
sweep missed something and the next step is more marks rather than more fixes.

The one thing that does want a real before/after is suspect 1's remaining half,
because it is a trade rather than a removal: the cost of building a large
file's text against the cost of whatever replaces it. Measure it as
`FileNodeReloadTests` measures its reload — a test with a file of a stated
size, not a session with a stopwatch.

## The deeper answer, still not attempted

The terminal does not need to share a queue with the project. Parsing runs on
main because the emulator and the renderer both live there, and moving it is a
real piece of work rather than a tidy-up. Everything above makes the queue
shorter; this is the one that stops the terminal caring how long it is.

---

Numbered after 0436, which is where the list had got to on the main working
tree — this was written on a branch that started before 0435 and 0436 existed,
and first took 0435. By the ordering in the README a bug that stops somebody
working belongs above everything currently open.

0435 is the PlantUML test that fails only when the suite is busy, which turned
up here too: three full runs on this branch failed in PlantUMLServerLiveTests,
MermaidLiveTests and SilentRuntimeTests, all of them timing-sensitive, all of
them green on their own and green again on a warm build.
