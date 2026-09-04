## Context

`MainWindowController.followsTerminal` starts from
`Settings.shared.followsTerminalProject` and is documented as a per-window
switch afterwards: "one window following a terminal about while another stays
where it was put is a reasonable way to work."

Two things set it. The checkbox in Settings writes the stored value and nothing
else; the control on the panel called `toggleFollowTerminal`, which flipped the
window's copy and nothing else. Neither told the other.

## Goals / Non-Goals

**Goals:**

- Following survives a quit however it was turned on.
- A preference changed while the app runs reaches the windows.

**Non-Goals:**

- Making the switch global. Two windows may still differ; what changes is that
  the last thing somebody *said* is what a new window starts from.
- Remembering it per project. Following is about how somebody works, not about
  a project, and the window it belongs to may open several projects in a
  sitting — that is the whole point of it.

## Decisions

**The panel's switch writes the preference.** The alternative — leaving it as a
window-only switch and telling people to use Settings — keeps a control that
silently forgets, and the report is what that costs. A control that looks like
a switch is a switch.

**Adopted only when the stored value changes.** `.abydosSettingsChanged` is
posted for every setting there is. Re-reading this one on each of them would
overwrite a window's own choice whenever anything else moved, which would
delete the per-window behaviour by accident while fixing persistence. So the
window remembers what the stored value was when it last looked and adopts only
a value that has actually moved since.

*Ruled out: observing the specific key.* `UserDefaults` KVO on one key would be
exact, and the app has one notification for settings and a `applySettings` that
every part already goes through; a second mechanism for one boolean is a second
thing to know about.

## Risks / Trade-offs

**Two windows and one preference** → A window that had its own answer keeps it
until somebody changes the preference somewhere, and then adopts it. That is
"the most recent thing anybody said wins", which is what a shared preference
means; the alternative is a window that ignores a change it was told about.
