# Tie tmux's status bar to the switch it belongs to

`478d54f7a` · 2026-08-04

Hiding tmux's bar only makes sense while these tabs are showing the same
list, so it is now a checkbox under "Tabs are tmux's windows" rather than
a button of its own — greyed out and unticked when that switch is off,
tickable when it is on.

Both sides follow at once, live:

- Turning the tabs off gives tmux its bar back, in the config and in the
  running server. Leaving somebody with neither a tab strip nor a status
  line would be this switch quietly breaking their tmux.
- The panel rebuilds its strip when a setting changes, so the tabs stop
  being tmux's windows there and then rather than at the next launch.

Settings controls now re-read themselves after any of them changes,
which is what lets one decide another's state.
