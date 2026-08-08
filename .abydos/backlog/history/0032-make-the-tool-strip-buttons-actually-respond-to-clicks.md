# Make the tool strip buttons actually respond to clicks

`4d76cc79e` · 2026-07-31

The tabs were wired correctly but fired from mouseUp alone, with no
mouseDown override. NSResponder's default implementation passes the
press up the responder chain, and the matching release is then not
reliably delivered to the view either — so the buttons worked only
sometimes, which read as the switching being broken.

Claiming the press fixes it. Switching between the two sidebar tools was
verified through the controller before this, so the fault was entirely
in the button.
