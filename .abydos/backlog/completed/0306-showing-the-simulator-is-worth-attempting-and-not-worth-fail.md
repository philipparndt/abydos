# Showing the simulator is worth attempting and not worth failing over

`9b30b49e8` · 2026-08-06

`open -a Simulator` stopped a run that had already built and booted, because
this Xcode beta ships no Simulator.app — not in Contents/Developer/
Applications, which does not exist, and nowhere else on the machine. The app
installs and launches on a simulator without it; only the window is missing.

So the window is attempted by path first, since `xcode-select -p` says which
Xcode is selected, then by name for the layout that has one, and the run
carries on either way. The path needs double quotes: single ones would look
right and pass `$(xcode-select -p)` through as a filename nobody has.

Verified against docscanner-ios on an iPad simulator: builds, boots,
installs, launches, and the app's own output arrives in the terminal — in
this case a dyld error from the app itself, which is exactly the sort of
thing that is worth seeing without opening Xcode.
