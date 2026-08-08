# Line up the tree's icons and keep names inside the row

`651950730` · 2026-07-31

Every icon was drawn into a square slot, but SF Symbols are not all the
same shape — a box is nearly square, a document is tall — so each was
stretched by a different amount and came to rest on a different optical
centre. Neighbouring rows visibly failed to line up, which .scad next to
.3mf made obvious. Icons now keep their proportions and are centred in the
slot instead.

Names were not truncated at all, so a long one drew over the row's rounded
selection and out of the pane. Both the name and the root's path subtitle
now ellipsize.
