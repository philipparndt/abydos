# Abydos 0.16.1

## The SOPS chip finds gpg

For a PGP recipient sops is a front end for gpg, and it shells out to the one
on its PATH. The chip gave the child the app's own environment, and an app
launched from the Dock has no Homebrew on its PATH — so the chip could find
sops and sops could not find gpg, and a working key read as a missing one
while the same `sops -d` succeeded in the terminal pane beside it. The chip
now hands sops the PATH the login shell has, as the language servers and the
terminal already did.
