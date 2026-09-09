# Abydos 0.20.1

## The Intel half that 0.20.0 promised

0.20.0's notes said the download runs on an Intel Mac, and the image carried an
Apple silicon binary only, so on an Intel Mac it refused to open exactly as
every release before it had. The build that produces both halves had been
taught to one release command and the publish script builds on its own, so the
instruction never reached the image people download. Found the same evening by
mounting the download and asking `lipo`, which is what should have been asked
before the notes were written.

This release is 0.20.0 with both processors in every binary — the app, the
hook, the bench and the backlog tool — and nothing else in it. The publish
script now asks for both, and the signing step refuses an app that is not
universal, in the same breath as it refuses a wrong bundle identifier or a
pinned UUID: cheaper to refuse than to explain afterwards.

An Apple silicon Mac already on 0.20.0 gains nothing from this one and need not
update.
