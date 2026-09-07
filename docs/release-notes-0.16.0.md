# Abydos 0.16.0

## An archive shows its contents in the tree

A downloaded Helm chart is a `.tgz`, and what you want from it is one look at
`values.yaml`. **Show Contents** on a zip, jar, tar, tgz or gz row in the
project tree opens it like a folder, listed from the archive's own directory
and unpacked nowhere. An entry opens in the editor read only, its tab saying
which archive it is inside, with syntax, find, structure and the hex editor
working as on any file; ⌘S says where the file is and names **Extract…**,
which writes that one entry beside the archive. Which archives you opened up
comes back with the tree's folds. `abydos-examples/multi-tier` carries its
chart packaged, as the case this is for.

## The View menu has shape

Fifty items in one column became groups named for what they are about — Git
Pages, Diff, Show As, Editor, Terminal — with the sidebar tools, the secrets
and the zoom staying at the top level. The submenu that read as "NSMenuItem"
is called Show As.

## Soft wrap cuts at words

A wrapped row ends after the last whitespace that follows a word, so a README
read with word wrap on no longer breaks `sentence` into `sen` and `tence`
wherever the edge fell. Indentation is never a place to cut, and a word longer
than the row is cut at the edge as before.

## Small things

- Making Abydos the default editor asks the system's own question once for
  text, and again only for a kind another application holds by name, rather
  than sixteen times in a row.

- The terminal strip's + and its chevron each light to where the other
  begins, rather than the + covering half the chevron.
