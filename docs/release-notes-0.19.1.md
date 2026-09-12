# Abydos 0.19.1

## Abydos opens where Gatekeeper cannot ask Apple

0.19.0 could refuse to open with "could not verify" offline or behind a proxy:
the disk image was stapled but the app inside it was not, so Gatekeeper had
to ask Apple on first launch. This release is 0.19.0 with the ticket stapled
to the app, and the release script now checks the app inside the finished
image. A 0.19.0 that already opened once needs nothing.
