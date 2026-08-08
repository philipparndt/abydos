# Send config files into the pod, and publish the image

`fcabb1e6d` · 2026-08-02

A service that is started with the path to its configuration cannot run in
a pod that has never seen that file, and "no such file" says nothing about
the pod being empty. The supervisor takes files as well as binaries now:
`/file?path=` writes one, confined to the work directory or /tmp so a push
cannot land in /etc. A configuration lists what to send, arguments naming
one of those files are rewritten to where it landed, and the editor has a
row for it.

The arguments themselves now travel with the push. Run mode used to start
the program with whatever the chart's values said, which is not what the
developer is working with.

Publishing: `make publish` pushes a real multi-architecture image to a
registry with no Docker involved. Everything inside is a static binary, so
each architecture is one layer of two files and the whole thing is a few
blob uploads and an index — which mkimage now speaks, logging in with what
`docker login` left in the keychain. A remote cluster cannot be handed a
tarball, so this is what makes one usable.

Two projects sharing a namespace no longer share a pod: the one named after
this project's release is the one it pushes to, and if there is none it
installs its own rather than borrowing somebody else's and looking, in the
logs, like a stale build.

Also: switching project in a window switches its editors — the previous
project's files stayed open, which is confusing when they are not this
project's files — and a file from outside the project is marked in its tab.
The commit subject field looked disabled beside the message box, so people
typed the message first and left the subject empty; it now looks like what
it is, and commit comes before push.

Verified against k3c-demo1: the config file arrives at /app/files/dev.json,
the argument is rewritten, and the program reads it in the cluster in both
run and debug mode.
