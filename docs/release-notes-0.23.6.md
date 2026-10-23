# Abydos 0.23.6

## A .vboard file opens as a board

With a vboard server named in Settings ▸ Tools ▸ vboard, opening a `.vboard`
uploads it there as a private temporary board and shows it in the tab, with
*Copy link* for colleagues to join. ⌘S writes the board back into the file,
and closing the tab removes it from the server. An empty `.vboard` starts a
new board. A file is only uploaded once it is opened for real, not while
arrowing through the tree or when a session is restored. Without a server, a
`.vboard` opens as text as before.
