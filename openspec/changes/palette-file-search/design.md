## Context

The command palette is `SwitcherViewController` in
`Sources/AbydosApp/Titlebar/ProjectSwitcherPopover.swift`. It already ranks
several kinds of thing into one list — `Row` is `.action`, `.header`, `.project`,
`.branch` — filters them from a search field, and takes VS Code's `>` and `:`
prefixes. Adding files is adding a fifth case and a source to fill it from.

The source is the whole design, because the two obvious ones differ by two orders
of magnitude. Measured on a work tree of 24,691 tracked files:

| source | files | time |
|---|---|---|
| `git ls-files` | 24,691 | **0.03–0.05 s** |
| `git ls-files --cached --others --exclude-standard` | 24,692 | **4.56–5.27 s** |
| `ProjectSearch.collectFiles()`'s walk, with exclusions | 25,564 | **3.05 s** |
| the same walk excluding only `.git` | 79,056 | 7.90 s |

The second row is the surprise and it decides most of what follows: asking git
for untracked-but-not-ignored files costs a hundred times more than asking for
tracked ones, and on this project it finds **one** extra file. It is expensive
for the same reason `git status -uall` was: to know what is untracked, git has to
walk the work tree, and the untracked cache cannot help when the answer must name
every file.

The relevant constraint from this repository's recent history: a project switch
held the main thread for 2,419 ms because two directory walks ran on it, and the
fix was to move them off. A palette that walked 25,564 files per keystroke would
be the same fault, thirty times worse.

## Goals / Non-Goals

**Goals:**

- Typing part of a path in the palette lists matching files and opens one.
- The index costs nothing per keystroke and nothing on the main thread.
- One set of exclusion rules, shared with project search rather than copied.
- A file saved a moment ago is findable without reopening the project.

**Non-Goals:**

- **Fuzzy matching.** Substring on the path first. Fuzzy ranking is a second
  change with its own evidence, and shipping it together would make it
  impossible to tell a ranking complaint from a source complaint.
- **Searching contents.** ⇧⌘F does that and keeps doing it.
- **A prefix of its own.** Files join the ranked list; `>` and `:` are untouched.
- **Indexing files outside the project.** Dependencies have their own tree
  section; whether they belong in the palette is a question for after this works
  for the project's own files.

## Decisions

### The index comes from `git ls-files`, tracked only

**Chosen** because it is 0.03 s against 3.05 s for the walk, and 4.56 s for the
git call that includes untracked files.

**`--others --exclude-standard` was ruled out on the measurement above**: a
hundred times the cost for one file. Its appeal is that it matches the walk's
answer almost exactly, and that is precisely what makes the cost indefensible —
it is paying five seconds for a difference nobody would notice, and paying it
again on every rebuild.

**The walk was ruled out as the primary source** for the same reason, but stays
as the fallback for projects that are not work trees, where there is nothing else
to ask. It is `ProjectSearch.collectFiles()` made shared rather than
reimplemented: its exclusions are already the ones this needs, and a second copy
would drift the first time somebody added a directory name to one of them.

**The consequence, and it is real**: a brand-new untracked file is not in the
index when it is built. That is what the filesystem-event decision below is for,
and it is a better answer than five seconds — a new file arrives as an event
naming it, so it can be added directly without asking git anything.

### The index lives in AbydosKit and is per project

`Sources/AbydosKit` holds no view code and is testable without a window, which is
where a thing with this much behaviour — two sources, a ranking, an invalidation
rule — belongs. The palette asks it for matches.

Per project rather than per window: two windows on the same project are asking
the same question, and building it twice is the cost this design exists to avoid.

### Filesystem events update the index rather than rebuild it

`FileSystemChange` already carries what is needed and says so in its own comment:
`paths` names the files FSEvents actually named, and `namesEveryPath` is false
"when the kernel gave up on describing a burst file by file and said scan this
subtree instead — a checkout, a build, an install."

So: when `namesEveryPath` is true, add and remove the named paths. When it is
false, mark the index stale and rebuild once, off the main thread.

**Rebuilding on every event was ruled out** because a build produces events by
the second, and each rebuild is a `git ls-files` over 24,691 files. The project
watcher already taught this lesson twice today — once as a `git status` per
event, once as a `loadGit` per event.

### Ranking: last component first, then path position

A match in the file's own name outranks a match in a directory above it, and an
exact name outranks a longer name containing it. Without the first rule, a
project with a `Git` directory answers `Git` with everything inside it and buries
`Git.swift`.

**A single "contains" with no ranking was ruled out** by that example: it is the
behaviour that makes people stop using the feature, and it costs one comparison
to avoid.

**Fuzzy subsequence ranking was ruled out for now** — see Non-Goals. It changes
what matches, not only what order they come in, and mixing that with a new source
would make a bad result impossible to attribute.

### Files join the `everything` scope, capped

The palette already caps projects at `projectLimit` before showing branches and
actions, for the reason its comment gives: without a limit the sections
underneath are pushed off. Files need the same cap and for the same reason —
25,564 candidates must not push branches and actions out of reach.

**A separate prefix was ruled out** because it makes the user classify the thing
before naming it, which is the opposite of what a palette is for.

## Risks / Trade-offs

- **A new untracked file is missing until an event names it** → the watcher
  supplies exactly that event; the risk is a project where watching has failed,
  and there the palette is no worse than the tree, which is also wrong.
- **`git ls-files` in a huge monorepo may still be slow** → it is 0.03 s at
  24,691 files, but the number that matters is the one measured on the project
  somebody complains about. Build it off the main thread and it is a delay before
  files appear, not a freeze — which is what the "not ready yet" requirement is
  for.
- **The index holds every path in memory** → 25,564 paths is small; a repository
  of a million files is not, and nothing here has been measured at that size.
- **Two windows on one project sharing an index** → shared state that both can
  invalidate. Today's crash was a `Project` written from two threads, so this one
  is built knowing it: the index is an actor or is confined to the main actor,
  decided when it is written rather than assumed here.

## Open Questions

- **Where the shared `collectFiles` should live.** It is currently a method on
  `ProjectSearch`. Whether it moves to a file-listing type that both use, or
  `ProjectSearch` exposes it, is a question for whoever writes it — both are
  defensible and the choice does not change any requirement.
- **Whether dependency files belong in the palette.** They have tree rows, so
  they are reachable; they are also the files somebody most often wants to read
  and least often wants to edit. Left out of this change deliberately, not
  decided against.
- **Whether the cap should be a cap or a "more" row.** The palette caps projects
  silently today. Whether files should say how many were not shown is a small
  question with no evidence either way yet.
