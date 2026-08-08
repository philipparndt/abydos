# The indexer builds where nobody else does, and pages move a page

`75376a859` · 2026-08-07

Two things about lists and locks.

sourcekit-lsp builds the package in order to index it, and by default builds
it into the package's own `.build` — the directory a terminal build uses. Two
builds in one directory take turns holding its lock and undo each other's
work, and where the toolchains differ they rebuild the world in turn. On this
machine a nine-second incremental build took over ten minutes while the
indexer had the directory, twice, and the second time left two hundred and
ninety-four compilers behind. It is given a scratch path of its own, beside
the caches: derived data, thrown away safely, and not one more thing inside
the checkout to ignore and to search by accident.

And the palette's list answers Page Up and Page Down, and ⌘↑ and ⌘↓ for the
ends. The rule is worth its own place because the edges are where these keys
are judged: an arrow at the end of a list stays where it is, and a page at the
end goes to the last entry rather than nowhere — the difference between a key
that feels finished and one that feels stuck. Headers are stepped over rather
than landed on, so a page is a number of entries and not a number of rows.

Both spellings of each key are answered: which selector a key sends depends on
the field it lands in, and a list that answers one of them works in some
places and not others.
