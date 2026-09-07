# Abydos 0.16.2

Two fixes.

## A committed SOPS file is not a leak

The exposure notice in the status bar counted a decrypted SOPS buffer among
the files whose values git might have seen, and over an encrypted file git
tracks it read *Committed to git*, naming a leak that is not there: what is
in the history is ciphertext, which is what SOPS is for. Its one offer, a
`.gitignore` line, would have taken the encrypted file out of the repository
it belongs in. The notice now asks git only about files whose plaintext is on
disk — a `.dec`, a dotenv — and a decrypted buffer, which lives in memory
alone, gets no notice.

## A URL that names no file neither wedges the window nor aborts the app

Two crash reports with one cause: an open-URL event can carry any string,
and a relative or non-file URL reached the project-root climb — which never
ended, 176 seconds and 34 GB into it — and the git runner, whose
`currentDirectoryURL` raises an Objective-C exception for a non-file URL that
Swift cannot catch. The entry now filters as dropped files already did, the
climb refuses what it cannot finish, and the git call answers with a failure
instead of an abort. A path that does not exist is still let through, because
git says so in words.
