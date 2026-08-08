# Rebuild the git panes when the project changes

`d8d4ed283` · 2026-08-01

Following the terminal to another project left the changes panel showing the
repository it had come from. Changes and branches are each built around one
repository and hold on to it, so a different project needs them built again.

Done once git has been read rather than when the project is set, because
until then there is no repository to build them around.
