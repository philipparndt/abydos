# Create folders from the navigator's context menu

`bc7a50452` · 2026-07-31

"New Folder…" creates one inside the clicked directory, or beside the
clicked file — right-clicking a file to make a folder next to it is the
same gesture, and refusing unless a directory was clicked is a rule
nobody would guess.

Names are checked before the file system is touched, so a rejection is a
sentence rather than a POSIX error. The rules live in IdeaiKit and are
tested without a window. A leading dot is allowed but reported when
dotfiles are hidden: the folder would be created and then apparently
vanish, which reads as a failure.

The tree is refreshed by the file system watcher rather than directly,
so the new folder is selected once the node exists rather than
immediately, when it does not yet.
