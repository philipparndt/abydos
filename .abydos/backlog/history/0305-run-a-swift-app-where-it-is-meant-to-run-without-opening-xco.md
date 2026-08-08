# Run a Swift app where it is meant to run, without opening Xcode

`3572f3b63` · 2026-08-06

A scheme is now something this project can run, beside its make targets and
its Go packages, and where it runs is a second choice next to it rather than
an entry per combination: a machine with several simulator runtimes installed
offers well over a hundred destinations for one scheme, and a list of a
hundred is not a list anybody reads. Where a scheme went last is remembered
with the project's session, so the play button repeats what you did.

Schemes are read from `xcshareddata/xcschemes` rather than from `xcodebuild
-list`, which takes about twelve seconds and answers with a scheme for every
Swift package a project depends on. Destinations do need `xcodebuild`, so
they are asked for once, when somebody opens the menu or runs a scheme, and
the menu fills in underneath the pointer when the answer arrives.

What that answer contains is most of the work. Placeholders name a family
rather than a machine; the "Designed for iPad" variant is a different product
directory that cannot be told apart by name; and everything under the second
heading is listed with the reason it cannot be used — usually a simulator
older than the deployment target, which on this machine is a hundred and
twenty of the hundred and forty lines. That heading has two spellings.

Running on this Mac opens the bundle rather than running the binary. Running
the binary is the obvious thing and it is wrong: a sandboxed app started from
a shell cannot be granted its container and exits at once with
"sandbox_extension_issue_file_to_process failed". `open` will not redirect to
a pipe or a tty either, so what the app prints goes to a file that is
followed while it runs, and the follower is stopped afterwards or the
terminal never looks finished. Verified against docscanner, whose macOS
scheme builds, launches and leaves nothing behind.
