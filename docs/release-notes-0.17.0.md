# Abydos 0.17.0

## The SOPS chip takes a passphrase

A PGP key with a passphrase could not be used from the chip: gpg has no
pinentry it can reach from a Dock-launched app, and the toast showed its
words about an ioctl. Now the first attempt is the one there was — an agent
that holds the passphrase, a working pinentry and an age key see no question
— and when gpg fails for want of a passphrase, the chip's place in the status
bar becomes a field naming the key. Return retries with what was typed,
Escape puts the chip back, and a wrong passphrase says so in the field.

The passphrase reaches gpg on a file descriptor through a small wrapper that
sops runs in gpg's place, and is never an argument, an environment variable,
a file or a toast. One that worked is kept in memory for the sitting, so
locking and decrypting again asks nothing; ⌥ on *Lock* forgets it.
