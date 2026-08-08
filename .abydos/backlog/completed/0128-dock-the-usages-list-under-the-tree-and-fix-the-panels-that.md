# Dock the usages list under the tree, and fix the panels that overlapped

`d71369154` · 2026-08-01

Three things about the panels that came out of using them.

They were drawn under their own titlebars: both were built to fill their
frames, so the heading landed on top of the title and the traffic lights.
The usages window no longer fills its frame, and the palette's field starts
below the chrome.

Down and up now move through the results while the search field still has
the keyboard. A search field handles those keys itself — they open its list
of recent searches — so they never reached the window and the list never
moved. Return opens, escape closes, from the field.

And a list of usages can be docked under the project tree instead of
floating over the code it is about. It is something you work through, and by
the second one a window covering what you are reading is in the way. The same
table moves across, so the scroll position and selection survive it; the
divider is placed once the split has a height, since setting one in a view
that is still zero tall leaves the docked pane filling the whole sidebar.
