# A terminal in a window of its own takes the terminal commands

`023cf30a2` · 2026-08-06

Every terminal command is written against `MainWindowController`, because
that is where a panel normally lives. A terminal dragged out has a panel and
no main window, so the commands reached nobody: the menu items were there, the
window was there, and the two never met — a new tab out on the second display
was impossible, which is the first thing anybody does in a terminal.

The item is sent down the responder chain now rather than typed to a class,
and the terminal window answers it. Verified by tearing one off and sending
the command through that window's chain: enabled, delivered, one terminal
became two. Down that window's chain and not the application's, because a
capture run has no key window and an app-wide send starts nowhere.

Note for whoever asked about ⌘D: nothing in this app binds it. New Terminal
Tab is ⌘T and the splits are ⌘\ and ⌘⇧\.
