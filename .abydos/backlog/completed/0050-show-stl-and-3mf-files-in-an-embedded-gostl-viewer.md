# Show STL and 3MF files in an embedded GoSTL viewer

`82cd59ad1` · 2026-07-31

GoSTL's package now vends a library alongside its application, so the
viewer is a tab beside the code rather than a second program. Opening an
STL or a 3MF shows the model, its dimensions and its volume; a .scad
stays a text file, since editing it is the point.

Its shader needed carrying over. GoSTL compiles Shaders.metal to a
default.metallib in its own Makefile, so a build that only asks SwiftPM
for the library gets a bundle without one and the viewer aborts on open.
The bundler compiles it — into the build directory's copy of the bundle
as well as the app's, because `Bundle.module` resolves to the build path
whenever it still exists, which it does on the machine that built the app.

The terminal cursor no longer blinks. A blink repaints the view twice a
second whatever the program is doing, which on a busy screen is hard to
tell apart from the program being slow, and the cursor is already the
only filled block on its line.
