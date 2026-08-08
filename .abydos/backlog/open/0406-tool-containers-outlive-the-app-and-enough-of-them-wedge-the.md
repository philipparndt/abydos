# 406. Tool containers outlive the app, and enough of them wedge the runtime

Found on this machine on 2026-08-08: eleven `container run --rm -i
plantuml/plantuml` processes, four of them a day old, the rest from a run of
the app that had already ended. Nothing was drawing a diagram. They were simply
never stopped.

With that many of them, Apple's `container` stops answering: `container ls`
hangs, `container images inspect` hangs, and so does everything in this app
that asks a runtime a question. Every render then starts another one that hangs
too. That is what the report of "the app spams the runtime with containers"
actually was — not a loop starting them deliberately, but nothing ever ending
them. `pkill -TERM` cleared all eleven, and the runtime answered in
milliseconds again immediately afterwards.

**One cause is fixed here.** The preview's deadline used to begin `guard let
self` — so a pane closed, or a project switched, while a render was hanging
left the render running with nothing left to stop it. It now stops the process
whether or not the view is still there, and follows the polite ask with a
`SIGKILL` two seconds later.

**What is left is the bigger half:**

- **Nothing reaps children when the app goes.** A subprocess is re-parented to
  launchd, not killed, and a crash runs no `deinit` at all. The app crashed
  today at 14:20 and its containers are what was found. Every long-running
  child this app starts has the same property: language servers, debug
  adapters, tmux clients.
- **There is no ceiling.** Nothing counts how many tool containers are in
  flight. One per pane per render, with each hanging for thirty seconds, adds
  up faster than anybody notices.
- **A wedged runtime is not recognised.** The right answer to a runtime that
  has stopped answering is to say so once and stop asking, not to start another
  container that will hang the same way. `ContainerImageStore` already
  remembers what it has learned about images; the same shape would do for "this
  runtime is not answering".

Worth checking on the way: whether `container run` left behind by a killed
parent also leaves a container behind inside the runtime, which `--rm` would
normally have removed.

---

Its number is where it sits in the queue, not what it is worth doing next.
Previously numbered 395.
