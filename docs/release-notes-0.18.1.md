# Abydos 0.18.1

## Links open in your browser again

*Make Default* claimed `public.html`, which made Abydos the system browser
and dropped every link `open` handed it. HTML is no longer claimed, and a
machine where it already happened hands the default back on the next launch.

## Compare, History, Blame and change marks work inside a submodule

Diffs, logs, blame and the gutter's change marks for a file inside a
submodule asked the superproject, which answered nothing. They ask the
repository that owns the file now, and a submodule's history opens as its own
log page.

## A submodule looks like a repository

The changes tree and the refs tree draw a submodule with the box the
Submodules section uses, and the folder's tooltip names the repository a
commit would go to.

## The trust strip waits until the answer is in

Switching to a project trusted by its remote no longer flashes *not trusted*
while git is still asked where it came from. Nothing runs until the answer is
in.

## Resizing with word wrap on is faster

Re-laying out a 68,608-line file on a resize took 2.3 s a frame and takes
0.17 s. Opening a large file is quicker for the same reason.

## The changes tree is names

Rows no longer end in `+192 −46`. The counts are in the folder tooltips.

## The git panel says how far through it is

The first read of a repository with many submodules shows *Reading 43 of 170
repositories…* instead of a spinner, and no longer runs a second command per
submodule for line counts.
