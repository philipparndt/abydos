# 4. Editing .gitignore does not un-grey the files it now includes

Adding `!backlog/` to `.abydos/.gitignore` and saving leaves the folders drawn
as ignored. They stay grey until something else forces a refresh.

The navigator colours a row from the git status it holds, refreshed on
filesystem events — but a change to `.gitignore` changes the status of files
that did not themselves change, so nothing marks them dirty. `git status`
would say so if asked; nobody asks.

Saving any `.gitignore`, at any level, should invalidate the whole cached
status for that repository rather than the one file that changed. There can be
several: the repository root, subdirectories, and `.abydos/.gitignore`.
`GitRepository.refresh` rebuilds everything already, so the work is
recognising the trigger — `ProjectNavigatorViewController.onFilesChanged` is
where the event arrives.

Worth checking `.git/info/exclude` and a global ignore file on the same path,
which have the same property.

---

Numbered 57 while it was being worked on, which is what a
commit message citing it means.
