# Abydos 0.6.2

One name, finished. 0.6.1 moved the development pod off `ideai` and kept the
Helm *release* prefix deliberately — a release names something that exists in
somebody's cluster, and changing it orphans that rather than migrating it.

That was the right argument about the wrong place. A release name is not read in
`helm list`. It is read in the pod name, next to the chart's own, every time
anybody runs `kubectl get pods`:

    ideai-go-service-abydos-devpod-d8b5785d5-kd442

Half of that had already moved. A name that is half renamed is worse than either
whole one — it reads as a bug in front of somebody — and the thing being
protected was a single `helm uninstall`.

The release for a project is now `abydos-<project>`.

## What this costs

A project whose pod was installed by an earlier version **is not upgraded**. The
new release is installed beside the old one, and the old one keeps running until
it is removed:

    helm uninstall ideai-<project> --namespace <namespace>

Both are found while both exist — they carry the same label — so what you get is
a duplicate in the pod list rather than a pod nothing can see. That is the whole
of it, and it is why this was worth doing now rather than never.

## Three more tests that could take the suite down

0.6.1 fixed a stash test that asserted a list had three entries with `#expect`
and then subscripted the third — `#expect` records and carries on, so under load
the subscript trapped, and a trap ends the whole test bundle rather than the one
test. Finding it took a crash report, because the log blamed the sixty-two
suites that happened to still be running.

It was not the only one. An audit of every force-unwrap in the suite found three
more of exactly that shape — an `#expect` that records a nil, and a line
immediately after that unwraps it anyway:

- `GitBranchesTests` force-unwrapped the branch it had just looked up.
- `ProjectGitRaceTests` checked `project.git != nil` and then wrote
  `project.git!` three lines later.
- `BacklogRunnerTests` force-unwrapped an item it expected to find on disk.

All four are now `try #require`, which stops that one test and lets the rest
finish. Nothing in the app changed — a test bundle that dies is not a shipped
binary — but a red run that accuses sixty-two innocent suites costs an
afternoon, and it had already cost one.

## Also

The Namespace field on a launch configuration suggests `abydos-dev` rather than
`ideai-dev`. It was only ever placeholder text, and it was the last `ideai` left
anywhere a person looks.

The images are unchanged. `pharndt/abydos-devpod:dev`, `:dev-go`, `:dev-native`
and `:dev-jvm` are the same ones 0.6.1 published — the release name is computed
by the app and handed to Helm, so nothing in the chart or the image moved.

What still says `ideai`, and is staying that way: the shipping bundle identifier
`de.rnd7.ideai`, which is the App Store identity and the key macOS files the
Local Network grant under; the jdtls data directory, whose rename costs a
project re-import; the scratch directory, which holds files somebody wrote; and
a long tail of names for temporary directories in the test suite, which nobody
sees.
