# Connect the gutter's play button to the run it was drawing

`de3f30188` · 2026-07-31

The marker rendered and the whole chain behind it existed — window,
editor area, editor group — but the code view's own callback was never
assigned, so the click reached the gutter and stopped there. The button
looked live and did nothing.

Verified end to end this time rather than by inspection: `func main`
opens a session titled "go run app" printing hello and exiting 0, and a
Makefile target runs `make run`, which builds and runs the binary. The
screenshot harness can drive the action now, which is what makes that
checkable at all — the previous claim that the buttons "render but the
click-through is unverified" was exactly the gap this bug lived in.
