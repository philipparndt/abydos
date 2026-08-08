# The watch list is written to from one place at a time

`8f0b770ac` · 2026-08-08

The test process died with a bad access inside `Array._makeMutableAndUnique`
— two threads writing into the same array, one freeing storage the other was
still using. Not a wrong value: a segmentation fault, which takes the whole
run with it and reads as the test runner being unreliable rather than as a
bug in this program.

Adding a watch starts a refresh, and so does every stop and every change of
frame, so more than one being in the air is the ordinary case rather than an
exotic one. Each of them walked `watches` by index and wrote into it between
awaits.

Now every change goes through a lock, and a result is applied to the watch
it was asked about by id rather than by index — which fixes the second bug
in the same lines: a watch removed while its expression was being evaluated
left every index after it pointing at the wrong row, or past the end.

The test spawns eight refreshes over twenty watches. It is a race, so
passing once proves less than failing once did — but it failed reliably
before this and does not now.
