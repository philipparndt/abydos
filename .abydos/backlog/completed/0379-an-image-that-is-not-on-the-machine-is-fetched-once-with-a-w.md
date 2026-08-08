# An image that is not on the machine is fetched, once, with a word about it

`0a76af8bf` · 2026-08-08

A named image that is not there is the ordinary case, not the exception:
it is what happens the first time anybody opens a project naming one.
Nothing fetched it, so the first render failed in whatever words the
runtime chose — and a pull that takes two minutes with nothing on screen
is indistinguishable from a tool that has hung.

So the pane asks whether the image is here, fetches it if not, and says
which image it is fetching while it does. Once, however many panes ask:
two opening together wait on the same fetch rather than starting two, and
the answer is remembered so every keystroke's redraw does not pay a
process launch to be told the same thing.

When it cannot be got, it says which of four things happened, because
each has a different answer: fix the name, sign in, get a network, start
the runtime. The runtimes' own words are long, differently worded from
each other, and mostly about themselves; anything not recognised keeps
their first line rather than inventing a reason.

The two runtimes spell the commands differently — `container images
pull` against `docker pull` — which is the sort of thing worth a test
rather than a memory.
