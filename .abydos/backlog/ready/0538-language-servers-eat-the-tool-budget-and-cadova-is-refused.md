# 538. Language servers eat the tool budget and Cadova is refused with a container message

> When working with cadova I get this error pretty soon in the preview panel:
> 12 tools are already running from images and none of them has finished. That
> usually means the container runtime has stopped answering.

No container is involved. A Cadova preview runs `swift run <product>` through the
user's shell, and the message names the one explanation that cannot be the cause.

## One list, two kinds of process, one counter

`ToolProcesses` has two doors and they share an array:

    public func adopt(_ process: Process) -> Bool {
        running.removeAll(where: Self.hasFinished)
        guard running.count < Self.limit else { return false }   // limit = 12
        running.append(process)

    /// Takes charge of a process that is **not subject to the cap**.
    public func track(_ process: Process) {
        running.removeAll(where: Self.hasFinished)
        running.append(process)          // same array `adopt` counts
    }

`track`'s own sentence is true only of the tracked process itself: it is never
refused. But it lands in the array `adopt` counts, so **every long-lived process
permanently spends one of the twelve slots**. A language server is started once
per language per project and stays for the session, and it never satisfies
`hasFinished`, so nothing ever reclaims its slot.

The cap's comment states the assumption that fails:

> A backstop rather than a budget: one preview pane renders one diagram at a time
> and *a project starts a handful of servers*, so nothing legitimate comes near
> this.

A handful of servers is exactly what fills it. On the reporting machine right now:
11 `sourcekit-lsp`, 13 `gopls`, 7 `rust-analyzer`, 3 each of `clangd`, `jdtls`,
`pyright` and `typescript-language-server` — not all this app's, but a project of
several languages plus a second window is over twelve on its own. Once there, the
next `adopt` fails and the first Cadova build of the session never starts.

## Why the message is worse than the refusal

`adopt` returning false is reported with `ToolProcesses.tooManyMessage`, which says
"running from images" and "the container runtime has stopped answering". For a
`swift run` that is three wrong claims in one sentence: nothing is from an image,
no container runtime is in the path, and nothing has stopped answering. Somebody
reading it goes and restarts their container runtime, which cannot help.

The refusal is also silent about *what* is holding the slots, which is the one
thing that would have made this diagnosable from the pane.

## Worth deciding

- **Two counters, or two lists.** The cap exists to stop a runaway of *short*
  tools, so it should count only those. Keeping tracked processes in a second
  array — still ended together, which is the type's real job — is the obvious
  answer, and `endEverything` then walks both.
- **Whether 12 is still right** once servers are out of it. It was chosen against
  an assumption that included them, and a Cadova build is minutes rather than
  seconds, so a pane legitimately holds a slot far longer than a diagram render.
  Say what the number is for.
- **What the message should say.** It has to name the kind of thing that is
  actually stuck, and ideally how many of each. "Twelve tools are still running"
  with a count of renders and servers is diagnosable; a claim about images is not.
  A tool that was never started from an image must not be described as one.
- **Whether a preview pane should be capped at all.** One pane already refuses to
  start a second build while one is running (`guard running == nil`), so the pane
  is self-limiting; the cap adds nothing for it except this failure. That is an
  argument for `track`-like treatment, and against it is that a pane can be opened
  many times over.

## Steps

- [ ] A project with a dozen language servers can still start a Cadova build
- [ ] Long-lived processes are still ended when the app ends — that is the whole
      point of the type and must not regress
- [ ] The refusal message names what is actually holding the slots and does not
      mention images or container runtimes unless one is involved
- [ ] A test that fills the cap with tracked processes and shows `adopt` still
      succeeds
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
