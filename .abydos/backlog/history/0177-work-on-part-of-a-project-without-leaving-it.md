# Work on part of a project without leaving it

`08ef8a810` · 2026-08-02

A repository is often not one thing. This one holds a package and an app;
ideai-examples holds eight projects; a work checkout holds a service, its
front end and three libraries. The tree has to stay whole — that is how
anybody navigates — but nothing else can: there is no one set of launch
configurations, no one module to build, no one work tree for git to act on,
no one root to hand the language server.

So one folder at a time is the subproject. Right-click it in the tree, or
pick it from the pill beside the project name, and the run configurations,
the build, the terminal's directory, git and the language server all follow
it. The tree marks it; the pill's cross gives the whole project back; the
choice is written down beside the project, so tomorrow opens where today
left off.

Git follows it properly, which is the point for a checkout of several
repositories: the scope is held on the project rather than passed to each
load, because a load started for the whole project and one started for a
subproject can be in flight at once and the last to finish must not be the
one that decides which repository this is. The changes, history and branches
panes are built around the scope too.

Found the branch pill had been racing git all along: in a repository small
enough for git to answer before the toolbar builds its items, the pill was
told a branch it did not exist to hear. It catches up now.

Verified against ideai-examples: opening native/odin-hello offers its
configuration and not the repository's, and opening git-scenarios/out/
uncommitted — a repository inside the repository — shows that repository's
three unstaged and one staged file, its history, and its branch.
