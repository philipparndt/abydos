# Never take the app down looking for the chart

`7ac9cc891` · 2026-08-02

`Bundle.module` is generated code that calls `fatalError` when the resource
bundle is not where it expects. Asking it for the development pod's chart
meant a build that shipped without one did not fall back to the next place —
it crashed, on the main thread, in the middle of pressing run in a cluster.
That is the crash report you sent.

The chart is looked for by hand now, in each place it could be: the resource
bundle a package target produces, beside the executable, inside the
application bundle, and in the repository when running from a checkout.
Nothing here can trap. Verified from the built .app, where it resolves to
Contents/Resources/ideai_ideai.bundle/devpod-chart.

Also: the settings and launch pages take the width they are given rather than
stopping at a column I had capped for readability.
