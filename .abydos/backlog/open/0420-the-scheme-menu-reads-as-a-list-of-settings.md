# 420. The scheme menu reads as a list of settings

The run control's menu shows the schemes with a tick beside the chosen one, and
a ticked list is what a settings menu looks like — "Word Wrap", "Show
Invisibles", things somebody turns on. Nothing in it says that picking one
*runs* the app, which is what it does.

The tick is not wrong about what it means: this is the scheme that will be
used, and the checkmark is macOS's own way of saying "this one". It is wrong
about what happens next, and that is the part somebody reads.

## Worth deciding

- **A run glyph on the item that will run.** `play.fill` beside the chosen
  entry rather than a tick — the same shape as the button the menu hangs off,
  so the menu and the button say the same thing. The rest of the items keep
  nothing, since a menu of play buttons says everything runs.
- **Say the verb.** A first item reading "Run WallDisplay2" above the list, and
  the list below it only chooses what "Run" means. More words, and it separates
  the two questions — what runs, and run it now — which are genuinely separate:
  the play button already answers the second.
- **Leave the tick and change the submenu.** The destinations submenu is where
  the running actually starts, so the scheme row could stop being clickable at
  all and exist only to open it. Fewer ways to start something by accident.

The first is the smallest and probably right. The second is what a menu with
room would do.

**Worth checking while there:** whether the ticked scheme and the ticked
destination mean the same thing to somebody scanning it. They are ticks at two
levels — one says "the scheme I will use", the other "the machine I will use" —
and after this is decided they should look like each other, whatever they end
up looking like.

`MainWindowController.fill(_:with:for:target:)` builds the destinations, and
the scheme list is above it in the same file.

---

Its number is where it sits in the queue, not what it is worth doing next.
