<!-- What this item changes about `version-control`. Folded into
     .abydos/backlog/spec/version-control.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       The working copy is shown as the folders it changed
       Staging a folder stages everything under it
       A folder says how much of it is on this side of the index
       The commit view keeps its place while files are written
       One question answers which branch the work tree is on
       A branch with no commits on it shows, quietly
       Push says which branch it cannot send
       The titlebar says which checkout, and opens the others
       Choosing a checkout opens it as a project
       A list of checkouts is ordered, capped and honest
       A checkout is dated by the metadata that moves
-->

## ADDED Requirement: Changes can be thrown away, from the unstaged list only

The changes pane's menu discards what a row covers: a file, or a folder and
everything under it. It is offered in the unstaged list and nowhere else.

Discard restores the work tree *from the index*, so over a staged row it would
throw away nothing that is staged — the change would survive, staged, and the
row would not go away. Meaning `restore --staged --worktree` there instead was
the other way to make it honest, and it is not what happens: a file staged and
then edited again is a row in each list, and discarding it from the staged row
would also take the later edit, which is only shown in the other one. Unstaging
first is recoverable and is the top item of the same menu. The diff view hides
*Discard Selected Lines* over a staged hunk for the same reason, so the word
means one thing in this window.

It is not offered over a conflict either. `git checkout` refuses an unmerged
path, so the entry would be one that always fails, and throwing away a
half-resolved merge is a question with more than one answer.

### Scenario: a modified file

- **Given** a tracked file with unstaged changes
- **When** it is discarded from the context menu and the confirmation is agreed
- **Then** the file holds what the index holds for it
- **And** it is no longer a row in the unstaged tree

### Scenario: the same file's staged row

- **Given** a file that is staged and then edited again, so it is a row in both
  trees
- **When** the menu is opened on its row under Staged
- **Then** there is no discard entry

### Scenario: an unresolved merge

- **Given** a file git reports as unmerged
- **When** the menu is opened on it
- **Then** there is no discard entry

## ADDED Requirement: Discard says how much it takes, and which of it is deleted

Discard is the one thing this pane does that has no way back, so it asks first,
and both the menu entry and the confirmation carry the numbers.

A folder says how many files it is about to take, the way Stage and Unstage
already do. Where some of them are untracked it says how many, because those are
two different losses on one gesture: a tracked file goes back to the version in
the index, and an untracked file is deleted from the disk, with no git object
left anywhere. Where *everything* covered is untracked the verb changes — over a
file git has never seen, "Discard Changes" is false, since there are no changes,
there is a file, and it is about to stop existing.

The confirmation names stash, which is discard with a way back and is already in
the same menu. Ignored files are not touched: `clean` is asked for `-fd` and
never `-x`, so discarding a folder does not also take the build output somebody's
`.gitignore` keeps out of the way.

### Scenario: a folder holding both kinds

- **Given** `Sources` has 40 changed files under it, 12 of them untracked
- **When** the menu is opened on the folder
- **Then** the entry reads `Discard Changes in “Sources” (40 files, 12 untracked)…`
- **And** the confirmation says the 12 are deleted from the disk and the other 28
  go back to the version in the index
- **And** it says the change cannot be undone, and names stash

### Scenario: a file git has never seen

- **Given** an untracked file `new.swift`
- **When** the menu is opened on it
- **Then** the entry reads `Delete “new.swift”…` and the button reads `Delete`

### Scenario: a folder with something ignored under it

- **Given** a folder holding a changed file and a file matched by `.gitignore`
- **When** the folder's changes are discarded
- **Then** the ignored file is still there

## ADDED Requirement: A discard only restores the paths git tracks something under

The paths a discard was asked for go to `git clean` as they are, and then to
`git checkout` only if git has something tracked under them.

Git validates every pathspec before it restores anything, so one path with
nothing tracked under it — an untracked file, or a folder holding only untracked
files — fails the whole restore with *"pathspec did not match any file(s) known
to git"*. Handing over both meant deleting the untracked half of a selection and
then reverting none of the rest, and reporting git's error for an operation that
had already destroyed something. Which paths those are is one `git ls-files` for
all of them, and the answer only decides which of the original paths to pass on:
a folder is still one argument, not the forty files beneath it.

### Scenario: a selection holding one modified and one untracked file

- **Given** `tracked.txt` is modified and `new.txt` is untracked
- **When** both are discarded together
- **Then** `new.txt` is gone from the disk
- **And** `tracked.txt` holds what the index holds for it
- **And** nothing is reported as having gone wrong

### Scenario: a folder holding nothing but untracked files

- **When** it is discarded
- **Then** the folder is gone, and git is not asked to restore it
