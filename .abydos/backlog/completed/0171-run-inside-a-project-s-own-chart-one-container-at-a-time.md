# Run inside a project's own chart, one container at a time

`63d28f4ad` · 2026-08-02

The development pod's chart is right for a service that has none of its own.
A real project has one: values files per stage, secrets through helm-secrets,
an application and a web front end in one pod, a cache beside them.
Reproducing that with a chart of ours would reproduce it badly, and the parts
that would drift — what the containers are given, what they can reach — are
the parts that matter.

So a configuration can name the project's chart instead. The chart is
installed as it is, and then one container of it is swapped for the
supervisor: same pod, same environment, same mounted secrets, same
neighbours, with the binary from this machine running in it. A pod holding an
application and a web front end is two configurations, one naming each
container; the other container goes on running what the chart says.

"In a cluster" and "In a cluster, with this project's chart" are two kinds of
configuration, so a simple service still needs nothing but a namespace.

Two things the cluster taught us on the way: helm must not `--wait`, because
what it would wait for is the image about to be replaced; and the patch takes
helm's name as its field manager, since the cluster records who owns each
field and a patch under its own name turns the next upgrade into a conflict
instead of an upgrade.

Verified against k3c-demo1 with a chart holding app, web and valkey: the app
container running the pushed binary with STAGE=dev and the chart's secret in
its environment, then the web configuration putting the supervisor in the web
container and handing app back to the chart.
