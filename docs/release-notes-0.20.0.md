# Abydos 0.20.0

## The download runs on an Intel Mac

The image is universal: one download, both processors, the same signature and
notarisation. Not tested on Intel hardware, but the Intel half runs under
Rosetta.

## A double-click on the title bar zooms once

It zoomed and came straight back, because both the title strip and AppKit
answered it. The strip no longer does, and your system setting decides.

## A readable light terminal, and a WCAG Level AAA theme

Every shipped palette's light half is darker, clearing 4.5:1 on every ground;
twenty theme values moved a shade for the same reason, and a test measures
every palette on every run. New in the Theme list: **WCAG Level AAA**, the
blue theme at 7:1 throughout, with a terminal palette of the same name. A
theme of your own can set `"floor": 7`. Light powerline prompts want light
text on their segments.

## Settings can be filtered

A field at the top of the settings sidebar matches titles and help text
across every section. ⌘F puts the cursor in it.

## The project tree keeps its place across a rebuild

The scroll position survives every rebuild of the tree, beside the expansion
and selection it already kept.

## A file opened from inside an archive is found in the tree

*Find File in Editor* on an entry opened from a zip finds its row.

## Behind the release

The tap checks GitHub for the tag and compares the image's digest with the
cask's checksum before writing anything. `abydos-diff` as a git difftool
opens the installed app, or the checkout's own build from one of its panes.
Most commits since 0.19.1 split long source files and change nothing.
