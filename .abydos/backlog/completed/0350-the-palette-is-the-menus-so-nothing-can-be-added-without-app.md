# The palette is the menus, so nothing can be added without appearing in it

`f10c63b28` · 2026-08-07

The palette held eight actions, written by hand beside the menu bar's own
list. Everything in it was something somebody had remembered to add twice,
and everything anybody added once was missing.

So it reads the menus. Every action a Mac app has is a menu item already —
that is the platform's rule, not one this app invented — and each item
carries exactly what a palette needs: what it is called, what key it answers
to, and whether it can be done right now. Validation decides the last of
those, the same validation that greys the menu item, so the palette offers
what the menus would offer and nothing that would disappoint. An action added
tomorrow is in the palette the moment it is added, with its shortcut, and
nobody has to know the palette exists. It performs them the way clicking the
item does, so targets and the responder chain are the menu's problem.

Shortcuts are shown, which is the other half of it: a palette that teaches
the key is a palette somebody stops needing.

Two things fell out. Menu names came out as "NSMenuItem" — a menu bar is
built by giving a titleless item a titled menu, and a titleless NSMenuItem
answers `title` with its own class name — and the application menu is now
named after the app, from the bundle, where the three items that say the name
had been saying "ideai" since the rename.

The preview modes are menu commands now, so they have keys — ⌃⌘1 to ⌃⌘4, the
sidebar's numbers a modifier along, in the order the tab strip lists them —
and the strip's own dropdown shows those keys, since that is where somebody is
looking when they wonder how to do it without the mouse. In a submenu of
their own, because "Split Right" is also a second editor pane and two
commands with one name in one menu is a coin toss.

Also: switching from Light to System stayed light. Every theme that is not
"system" forces an appearance on the app, and `systemIsDark` asked the app —
which answered with what it had been forced. It asks the system now, and in
system mode nothing is forced at all, so the controls follow along too.
