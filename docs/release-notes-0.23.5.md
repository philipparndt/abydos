# Abydos 0.23.5

## Bursts of file changes no longer hold the processor

Creating or deleting thousands of files at once inside an open project — a
worktree added by an agent, a build, a checkout — kept Abydos busy for as long
as it went on, and in a project with many submodules at several hundred percent
processor. A single save still updates the tree's colours and the changes pane
at once; during a burst they update every few seconds and once more when it
ends, while new and removed rows appear in the tree as they happen.

## The changes pane re-reads only the submodules that changed

In a project with submodules, a saved file or a git operation in one submodule
re-reads that submodule, not all of them. A commit, a checkout or a pull still
reads everything. In a 60-submodule test, the `git` processes started during a
30-second burst fell from over 7,000 to about 200.
