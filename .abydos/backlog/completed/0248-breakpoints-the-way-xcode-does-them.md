# Breakpoints the way Xcode does them

`54edff3d4` · 2026-08-04

The line number is the breakpoint. Click it to make one and the number
sits inside a blue tag pointing at its line; click the tag to turn that
breakpoint off — pale, still there — and again to bring it back; drag it
out of the gutter and it goes, with the puff that says so; right-click it
for edit, enable or disable, disable or enable the others, and delete.

A disabled breakpoint is kept and not sent to the adapter: it is one
somebody wants back later, not one they want now. Since only the enabled
ones are sent, the verified flags coming back are matched against those
rather than against the whole list, which had been marking the wrong
ones bound.

Folding moved to a column of its own at the right of the gutter, and only
the chevron folds now. The line number cannot both make a breakpoint and
collapse the code somebody was aiming at.
