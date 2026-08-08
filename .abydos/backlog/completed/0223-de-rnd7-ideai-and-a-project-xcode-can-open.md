# de.rnd7.ideai, and a project Xcode can open

`2bd5a79f1` · 2026-08-03

The identifier the App Store will know the app by, in an Info.plist that is
now a file rather than a heredoc — the hand-rolled bundle and Xcode copy the
same one, so the two cannot disagree about what the app is called or what
version it is.

Settings are keyed by identifier, so changing it would have looked like every
preference being forgotten at once. They are carried over on first launch:
copied, not moved, so an older build still finds its own, and anything
already set in the new domain wins. Checked by running it and reading the new
domain back — appearance, terminal scheme, the tmux switches, all there.

The project is generated from project.yml with xcodegen and gitignored, the
way yacal's is: `make xcode` opens it, `make xcode-build` builds it the way
App Store Connect will.

For that to work with one dependency graph, the window layer is now a library
of the package — `IdeaiApp` — and the executable is the four lines that make
an application and run it. Two declarations of the same path package built
the 3D viewer twice and the link failed with a page of "multiple commands
produce"; one package, one graph, and both builds compile the same sources.
