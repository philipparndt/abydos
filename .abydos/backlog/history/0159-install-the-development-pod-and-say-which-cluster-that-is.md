# Install the development pod, and say which cluster that is

`b1ede4433` · 2026-08-02

Two bugs in one path. The chart travels in a bundle of its own beside the
executable, and the app looked for it in its own bundle — which is what
"the chart is missing from this build" was really saying. And the install
was given the configuration's context verbatim, so a configuration
following the current one asked helm for a cluster called
"${currentContext}".

Installing is now something a configuration allows rather than something
that happens: on by default, because this is a development cluster and
stopping to say "install this first" helps nobody, and off for a team
whose pipeline installs its own.
