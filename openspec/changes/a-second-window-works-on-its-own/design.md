## Context

Three layers, each with the word "window" or "session" in it, and the report
was about all three at once:

| Layer | What collides | Rule |
|---|---|---|
| Abydos project | two windows on one project | the window that has it is raised |
| tmux session | two clients on one session | the second gets a grouped session |
| tmux window | two windows showing the same tmux window | the other is raised, by a click or by tmux's keys |

A tmux session has one current window, and every client attached to it shows
that one. That single fact is what made the report's terminals "act weird", and
it is why the middle layer has to be solved in tmux's terms rather than in
Abydos's.

## Decisions

**The project rule wins.** Where a tmux session and an open project point at
different answers — a session chosen in the picker whose folder is open in
window 1 — window 1 is raised. Otherwise File ▸ New Window would be the way
round the rule, and one project in two windows would need an answer to which of
them writes `.abydos/session` and when; it has none, and nobody has asked for it.

One question, asked in one place: `AppDelegate` answers "which window shows this
root", standardised, skipping torn-off windows, and `open(projectAt:)`,
`newWindow`, the picker and `follow(reported:)` all ask it. `follow` lives on the
window controller and asks through the delegate, as the switcher already does.

**A grouped session, made by Abydos, only when there is a collision.** A window
alone on a session stays on the base session exactly as now: `tmux new -A -s
<base>`. Only a second window gets `tmux new -t <base> -s <name> ; set-option -t
<name> destroy-unattached on`, with the status-bar option and `allow-passthrough`
set on it as the attach already does for the base. Collisions are found two ways:

- **at attach**, where `sessionToAttach` already decides the session and can ask
  whether another window's panel is on it;
- **after a switch**, in `refreshTmuxWindows`, which already learns the client's
  session every half second. Finding it equal to another window's, the panel
  makes the grouped session, selects in it the window the client was showing,
  and moves the client there with `switch-client -c <tty>`.

The second path has a window of up to half a second in which both clients are on
one session; a tab clicked in the other window in that half second still moves
both. Accepted: it needs two hands and closes itself.

**`destroy-unattached` instead of cleanup code.** A grouped session that only
exists because a window looks through it should end with the window, including
when the app crashes or is killed. tmux does that itself; the app removing it on
close would not survive the cases that matter.

**Groups are recognised by tmux's `session_group`, not by name.** The session
menu, *Close Sessions…* and the picker show a group as one row under its base,
and the attach rule finds the group of a base that has gone, by asking tmux
which group a session is in — so the naming scheme below is cosmetic, and a
session somebody grouped by hand outside Abydos is treated the same.

**The project remembers the base.** `ProjectSession.tmuxSession` is written from
`mirroredTmuxSession`; a grouped session's base is written instead, since the
grouped one is gone the moment the window is.

**Tab clicks and tmux's keys both raise the other window.** A click on the
strip reaches Abydos before tmux, so it raises the other window and does
nothing else. `C-b n`, `C-b w` and `C-b 1` reach tmux first, so Abydos hears of
them at the next reading and then raises the other window and takes this one
back to where it was.

This was first decided the other way — let through, with a note — for fear of
`C-b n` bouncing. It was reversed after the first test, 2026-10-26: `C-b w` in
the second window onto the first window's tmux window left both on it, and with
`window-size latest` and `aggressive-resize on` the two windows, on two
monitors, resized it between them. The person expected to be taken to the
first window. `C-b n` across that window now stops on it, which is the price.

Which tmux window another Abydos window shows is compared by `window_id`, which
a group shares.

**Seeded records keyed by `window_id`.** `RunningSessions.seededKey` is
`@<session>:<index>` today; two sessions of a group made two records of one
agent. Keyed by `window_id`, with the set of sessions that seeded it beside it,
so `forgetSeeded(inTmuxSession:)` takes one session away and drops the record
only when none is left. `TmuxMirror.windows` adds `#{window_id}` to its format.

**The picker is a list, like the switcher.** Projects first, then a section of
the server's sessions from `list-sessions` with `session_path`,
`session_windows`, `session_attached` and `session_group`, the agent state from
`RunningSessions`, and which Abydos window is attached. One `list-sessions` when
it opens; nothing polls while it is up.

**The "Open projects in a new window" setting stays** and keeps meaning what it
means for the switcher. File ▸ New Window opens a window whatever it says,
because that is what the item is called.

## Ruled out

- **Leaving the shared session as it is.** It is the report.
- **A separate, ungrouped session per window** (`tmux new -s <base>~2`). The
  second window cannot reach the agent in the first except by joining its
  session — the report again — and its own windows outlive it with nobody to
  come back to them, or die with work in them if killed.
- **Switching the client back after tmux's own keys.** Abydos learns late, the
  person sees a flicker, and `C-b n` can never pass the window the other Abydos
  window shows.
- **A tmux hook telling Abydos of switches** rather than the half-second poll.
  `BottomPanel+Tmux` explains why it polls — a hook has to reach back into this
  process — and nothing here changes that.
- **Keeping ⌘N on the front project, as a grouped second view.** It leaves a way
  round the project rule, which is the rule the person asked for.
- **An empty window from ⌘N.** A window here is a project; one with nothing in
  it is a window to close.

## Found while building it

Probed on tmux 3.7c, on scratch servers started with `-f /dev/null` — the
maintainer's config restores every saved session into any new server through
continuum, so a scratch server without that flag is a copy of somebody's work.

- **A grouped session starts on its group's first window**, not on the current
  one. Moving a client to one selects the window it was showing first.
- **`destroy-unattached` set on a session with no client ends it at once.** It is
  set in the same command line as the attach, or after the client has been
  switched over. It then ends the session both when its client detaches and when
  the client is switched to another session.
- **`set-option -t =name` answers "no such session"**, and `-q` makes that
  silent. Options are set on the bare name; the other commands keep `=`.
- **A group keeps its name after the session it was made from has gone**, and
  `new -t <member> -s <name>` puts that name back into it.
- **A panel whose tabs are this app's own polled nothing**, so the decision at
  the poll could not see `C-b w`. Nearly everybody's terminal is in that mode.
  `TmuxClientWatch` reads every client with one `list-clients` twice a second,
  only while two or more windows are open, and hands each unmirrored panel its
  session and window; the mirrored ones keep their own poll.
- **`C-b w` to a window in another window's session moves that window too**,
  before Abydos hears of it — it selects the window in the shared session. The
  window that was there notes which tmux window it had in front, and once the
  arrival has been moved to its own session, puts it back. A change made there
  with tmux's own keys in the second before is put back with it.

- **Another program's client is a collision too.** The second test, 2026-10-26,
  ran beside the installed Abydos, whose terminal had been on `firefly` all
  morning; the test copy's window attached to `firefly` beside it, and the two
  shared one current window and one size the way two of this app's windows had.
  A session with any other client attached is taken: at attach, by
  `session_attached`; on arrival, by `list-clients`. The client watch now runs
  with one window open as well, and keeps the last windows every client on the
  server had in front, so an outside client a `C-b w` from here moved is put
  back. An outside client cannot be raised, so standing on its tmux window is
  not refused.

- **tmux 3.7c draws an empty `C-b w` / `C-b s` while a grouped session is the
  newest.** `window_tree_build` sets `s = l[n - 1]` once and tests that session,
  not `l[i]`, when folding groups, so every session is skipped whenever the last
  one is a group member other than the client's own. A grouped session Abydos
  makes is always the newest, so every other client on the server — another
  Abydos, iTerm — gets a black list, and the first key closes it. Fixed in tmux
  3.8 (`s = l[i]`); `choose-tree -G` is unaffected. This was the black console
  of the second test.

- **A grouped session is usually gone by the time its window steps back to
  it.** Third test, 2026-11-09: window 1 had attached as `abydos~2`, beside
  another client, then walked into `veHub Architecture` and onto window 2's
  window. `destroy-unattached` had ended `abydos~2` as it left, so stepping away
  found nowhere to go and the two stayed on one window. The way back is now the
  session if it is free, and otherwise a new grouped session in its group.
- **The first reading of a mirrored panel came before its client.** It read the
  session the panel was configured for — the base, not the grouped session it
  was joining — and "arrived beside" there, moving the other window. Arrival is
  judged only once the client is on the server.
- **Every case is driven by a script now**, `make windows`: a scratch server,
  the person's example sessions, a terminal in another program where a case
  needs one, and `switch-client` from outside standing in for `C-b w`. A tab
  click and the picker are not in it; they are UI, and a driven verb covers each.

- **A closed window put its terminal on the other's.** Fourth test,
  2026-11-09: `C-x y` in window 2 closed its tmux window, tmux put the group on
  the window it had shown before — window 1's — and stepping away had nowhere to
  go back to, so both typed into one. A window that has gone is now told apart
  from a window chosen: nothing is raised, the terminal moves to a window nobody
  has in front, and with none it leaves tmux. A new window instead was ruled out
  by the person: closing windows would never end. Another session was ruled out
  too: it is other work, and a plain shell surprises less.
- **`display-message -t <window_id>` exits 0 for a window that has gone**, on
  tmux 3.8, so whether one exists is asked of `list-windows -a`.
- **`C-b s` could never enter a session another window was on** (review of
  #35). It lands on the session's current window — usually the other window's
  — and was stepped back from like a chosen one. tmux does not say which key
  moved a client, so arriving from another group is now treated as entering:
  beside, on a window nobody has in front, as a joining window does. Within
  the group a window was chosen, and stepping away stays. The price: a `C-b w`
  from another session onto exactly the other window's tmux window lands
  beside it rather than raising it.
- **What a panel knew about its client outlived the client** (review of #35):
  the windows it showed, its grouped sessions, the session it attached to. It
  is dropped when the client is seen to leave and when a new one attaches. A
  project switch keeps it, since the terminal and its client stay.
- **Another window's grouped session is the same session** for news from an
  agent in it: compared by the base each window knows it made, so a window on
  `<base>` does not switch its client into the other's `<base>~2`.

## Decided while building it

- **The grouped name is `<base>~<n>`**, the lowest free. Seen in `tmux ls`; the
  maintainer may still prefer another once it is in a real `C-b s`.
- **"Open in another window → Go there" is a toast in the window that walked**,
  with *Go there* as its action. The panel's own line was the alternative; a
  toast needed no new view and is shown in that window.
- **The picker is the ⇧⌘P palette in a `.newWindow` mode**: projects with a note
  (*open*, *tmux · 3 windows*), the server's sessions with their windows, agents
  and the window on them, and *Open…*. Filtering matches names only.
- **The attach decision is made when the terminal starts** (`attachCommand`),
  not in `sessionToAttach`: that is where the command line is built, and it is
  asked again on every reattach.
- **Only the window that moved steps away**, judged once per arrival: the window
  that was already there has not changed, and an arrival judged when it was
  regrouped is not judged again against tabs that have not caught up. A first
  version did, in mirrored mode, and stepped away from a window the other had
  just been put back from.

## Open

- **`C-b n` cannot pass the window another Abydos window shows.** It stops
  there, raises that window, and this one stays where it was.

- **A window that joins a group starts on the first window nobody else has in
  front.** Settled after the first test, which needed the same rule.
- **Closing a group in *Close Sessions…*** closes every session in it, and the
  toast counts each — one row ticked can say "2 sessions closed".
