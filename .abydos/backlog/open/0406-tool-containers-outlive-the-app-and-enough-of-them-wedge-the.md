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

Three of those are now done — every tool process is registered with
`ToolProcesses` and ended when the app goes, including out of the uncaught
exception handler, which is the exit that left the eleven; renders past a cap
of twelve are refused with a sentence saying what that means; and a runtime
that misses its deadline is reported once and then answered from memory
instead of being asked again.

**What is left is the half that was only a question, and the answer is bad.**
Killing the `docker run` that started a container does not stop the container:

    docker run --rm -i --name probe alpine:3 sleep 60 &
    kill -9 $!    # container: still up
    kill -TERM $! # container: still up after ten seconds

So `--rm` never fires, and everything above ends *processes* while the
containers behind them keep running. Two of today's symptoms are unexplained
without this — a runtime service that wedges under load nobody can see, and
`container ls` hanging long after the processes were killed.

Ending a container means asking the runtime to remove it, which means knowing
which one it is. Naming it at `run` time — `--name abydos-<something stable>`
— is the readable half; the removal verb is the half to check, since docker's
`rm -f` has no confirmed spelling in Apple's CLI. It could not be checked here:
that CLI was wedged badly enough that even `container --help` never returned.

Worth doing at the same time: a name has to be free before it can be reused, so
whatever starts a container should remove a stale one of the same name first
rather than failing with "name already in use" after a crash.

---

Its number is where it sits in the queue, not what it is worth doing next.
Previously numbered 395.
