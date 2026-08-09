# 415. The verbs somebody types all day build release

`CONFIG ?= release` in the Makefile, so `make build`, `make run` and `make open`
all compiled with whole-module optimisation. Measured on a quiet machine, after
touching one file:

    make build                 98 s
    make build CONFIG=debug     9.2 s

Ten to one, paid every time somebody looked at the app.

## Decided

**`run` and `open` build debug; `build` and `install` do not.** The first of the
two options in this entry: nobody who types `make build` expecting something
shippable is surprised, and the two verbs that mean "let me look at it" stop
paying ninety seconds for an optimisation that only matters to somebody using
the app rather than trying it.

`run` and `open` took `build` as a prerequisite, which cannot carry a
configuration of its own, so both now call `$(MAKE) build` the way `dev` already
did. The default is not hardcoded to debug there, because that would silently
ignore somebody saying otherwise:

    DEV_CONFIG = $(if $(filter command line,$(origin CONFIG)),$(CONFIG),debug)

So `make run` builds debug, `make run CONFIG=release` builds release, and only an
unsaid CONFIG becomes debug. `bundle.sh` already prints `==> Building (config)`,
so which one is happening is on screen either way.

---

Previously numbered 415 throughout; written and finished the same day as 403,
which measured it.
