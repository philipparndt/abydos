# Abydos 0.19.1

## Abydos opens where Gatekeeper cannot ask Apple about it

0.19.0 dragged out of the disk image could refuse to open, with macOS saying
Apple "could not verify" it was "free of malware" — for a build signed with a
Developer ID and notarised, on the machine that had just been handed the image.

Notarising leaves a ticket, and stapling puts a copy of that ticket inside the
thing that ships, so Gatekeeper can read it without asking anybody. The image
was stapled and the app inside it was not: stapling a disk image does not staple
what is in it, and the app was stapled after the image had already been made, so
the ticket went to the copy left behind in the build directory rather than the
copy people drag to Applications. Without one, Gatekeeper has to ask Apple over
the network on first launch — and that question has three answers rather than
two: yes, no, and no reply. Behind a filtering proxy, on a captive portal,
offline, or during an outage at Apple's end, the third is what comes back, and
it is shown to you as the second.

It was not only the app. Every helper it starts is assessed as it is spawned, so
*Open Anyway* was not a way round it either: it got the window up and left the
helpers being killed behind it.

This release is 0.19.0 with the ticket where it belongs and nothing else in it.
An app that has already opened once is not asked about again, so a working
0.19.0 stays working and there is nothing to do; a 0.19.0 that would not open
needs this one.

The release checks it now by mounting the finished image and reading the ticket
off the app inside it. Every cheaper check passed: an image packaged the wrong
way still signs, still notarises, and still satisfies Gatekeeper on any machine
that *can* reach Apple — which is the kind of machine releases are built on.
