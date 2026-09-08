# Abydos 0.18.1

## Links open in your browser again

An earlier version could make this machine's default browser an editor.
Taking the handler for `public.html` is how macOS is told which application
is the browser, and the `http` and `https` schemes follow whoever holds it —
so `open` on a URL handed the link to Abydos, which declares no URL scheme
and does nothing with one. The link was dropped and the command still
reported success, and nothing in the bundle mentions `http` anywhere, which
is why it was hard to see.

*Make Default* asked for every file kind the bundle declares, and HTML was
among them. It is now declared but never claimed: the editor is still offered
for a web page under *Open With*, which claims nothing, and only the taking
is refused. Where it already happened the next launch hands the default back
to whatever the system chooses instead and says so, because fixing the taking
cannot reach a machine it has already happened on.

## Compare and History work inside a submodule

*Compare ▸ Against Last Commit* on a file in a submodule said the file
matched the last commit when it did not, and *Compare ▸ History…* opened an
empty log. A superproject holds a submodule as a gitlink rather than as a
directory of files, so a diff or a log for a path inside one exits
successfully with nothing to say — the one shape of failure that reads as an
answer. Both now run in the repository that owns the file, and a submodule's
history opens as its own log page, named for it.

The diff tab from the changes pane had the same fault with a different
symptom: finding nothing to diff, it fell back to comparing the file against
nothing and drew every line as added. It reads the real diff now, and staging
or discarding selected lines from it goes to the right repository too.

## A submodule looks like a repository

A file changed inside a submodule appeared once under *Working copy* and
again under *Submodules*, and the first of those read as a change to the
project you have open. It is one fact in two groupings, both deliberate — the
working copy is the whole estate, the other is per repository — but nothing
said which of those folder rows *was* a repository. The changes tree and the
refs tree now draw a repository with the box the submodules section already
uses, so a directory and a submodule are told apart at a glance, and the
folder's tool tip says which repository a commit would go to.

## The trust strip waits until the answer is in

Switching to a project trusted by the host it came from showed *not trusted*
for a moment and then took the strip away again. Trust by remote cannot be
answered without asking git where the project came from, and the strip went
up before that answer arrived. Not knowing yet is no longer treated as not
trusted — for the strip. Everything that runs still refuses until it knows,
because nothing may run on a guess.

## Resizing with word wrap on

Dragging the window narrower with word wrap on was slow on a large file. A
resize changes the wrap width, so unlike a scroll it has to work out where
every line breaks again, and almost all of that time was going into the walk
over the file's lines rather than into the wrapping. On a 68,608-line crash
report the whole re-layout was taking 2.3 seconds a frame; it now takes 0.17,
and the same walk made opening a large file quicker as well.

## The changes tree is names

Every row in the changes pane ended in `+192 −46`, and every folder in a
tally as well. Three columns of numbers, and the deepest paths cut to make
room for them. The pane is read to find which file changed — how much it
changed is one click away in the diff beside it — so the rows are names now,
with the full width. What the folders were saying is in their tool tip, which
is where the partial-staging arithmetic was already explained.

## The git panel says how far through it is

Opening the changes pane on a repository of two hundred submodules took a
minute and a half the first time after a restart, behind a spinner that looks
exactly like a pane that has hung. Almost all of that is the first read of
each submodule's working tree, waiting on the disk. The wait is still there,
but the strip over the pane is a bar now: *Reading 43 of 170 repositories…*.

The pane also asks for less. It ran a second command per submodule to work
out the line counts at the end of every row, and those numbers are gone.
