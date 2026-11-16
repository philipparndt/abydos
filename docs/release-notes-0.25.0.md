# Abydos 0.25.0

## File ▸ New Window asks what to open

It no longer opens a copy of the window in front. A list of projects and of
the tmux server's sessions comes up; a project opens in a window of its own,
and a session opens a window on the folder it was started in with its
terminal attached. Choosing something another window has open raises that
window.

## A project is open in one window

Every way into a project raises the window that has it. A terminal that
`cd`s into a project another window has open, with following on, leaves its
window where it is and offers *Go there*.

## Two windows' terminals no longer move each other

A terminal that arrives at a tmux session another window or another terminal
program is on gets a session of its own in the same group, named
`<session>~2`, so each window keeps its own tmux window. It goes when its
window does, and the session list shows it as one row with its session. A
session you grouped yourself keeps its own row and is never closed with its
neighbour.

## A tmux window is in front in one window at a time

Choosing a tmux window that is in front in another window — by its tab, or
with `C-b w` or `C-b n` — raises that window, and this one stays where it
was. Revealing an agent's terminal and reopening a project follow the same
rule. Closing a tmux window that would leave a terminal on another window's
moves it to a free one; with none left, it leaves tmux and says why.

## An agent is counted once

The pill counts an agent per tmux window, however many sessions show it.

## Use tmux 3.8 or later

3.7c draws an empty `C-b w` list while a grouped session is the newest on the
server. A running server has to be restarted to get the fix.
