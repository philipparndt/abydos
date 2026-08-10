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

## Not fixed, and where to look next

`idle` is still 83% of the stalls and 8,776 seconds of them. Ranked by how
likely each is to hold the main queue while somebody types, from a sweep of the
whole app:

1. **`LanguageService` `didChange`** — `EditorViewController.swift:1032` builds
   the *entire file* as a `String` on the main thread every 0.4 s of typing,
   `LSPClient.swift:519` serialises it with `JSONSerialization` and then does a
   **blocking `write` to the server's stdin, on the main thread**. A server that
   is not draining its stdin blocks the app.
2. **`LanguageServers.suits()`** — a depth-2 directory walk per server
   definition, in a loop over every definition, from three `@MainActor` callers
   (`LanguageService.swift:154`, `:171`, `:249`).
3. **`refreshGitStatus`** — `ProjectNavigatorViewController.swift:231` awaits
   the git actor **once per tree node**, so each refresh floods the main queue
   with thousands of continuations that interleave with the terminal's own
   2 ms drain. The git subprocess is correctly off-main; the shape of the loop
   is the problem.
4. **`TextDocument.save`** — `TextDocument.swift:470` serialises the whole rope
   and does an atomic write on the main queue after every typing pause.
   Everything else in that file is on `engineQueue`; this one piece is not.
5. **`UserShell.loginPath`** — a `static let` that runs the user's login shell
   and waits up to five seconds. Warmed on a background queue at launch, but
   whoever asks first while that is still running pays for it on their thread.
6. **`DiffView.setDiff`** — `GitPatch.parse` plus two full tree-sitter parses
   inline on the main thread, bounded only at 5,000 lines.
7. **`DAPClient.stop`** — busy-waits with `usleep` for up to half a second,
   reached from main-thread actions.

**The cheapest next step is to make the log answer this rather than guess.**
`StallWatch.threshold` is 200 ms, which hides the whole 16–200 ms band that
makes typing feel bad, and only five call sites are marked. Dropping the
threshold and marking the seven above would turn "idle" into names, and none of
that changes behaviour.

The deeper answer, which nothing here attempts: the terminal does not need to
share a queue with the project. Parsing runs on main because the emulator and
the renderer both live there, and moving it is a real piece of work rather than
a tidy-up.

---

Numbered after 0436, which is where the list had got to on the main working
tree — this was written on a branch that started before 0435 and 0436 existed,
and first took 0435. By the ordering in the README a bug that stops somebody
working belongs above everything currently open.

0435 is the PlantUML test that fails only when the suite is busy, which turned
up here too: three full runs on this branch failed in PlantUMLServerLiveTests,
MermaidLiveTests and SilentRuntimeTests, all of them timing-sensitive, all of
them green on their own and green again on a warm build.
