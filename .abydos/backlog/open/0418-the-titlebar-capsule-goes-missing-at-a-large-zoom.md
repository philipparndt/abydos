# 418. The titlebar capsule goes missing at a large zoom

-> it is not missing, when there is not enough space it is moved to a hamburger menu.
-> the text is scaled, but not the box arround. The pill is getting slimer instead of higher

Reported as "the project selector is not scaled with the rest of the UI",
alongside the toasts — but it is not the same fault, and the difference is
worth having before somebody goes looking for unscaled numbers.

**The toasts were unscaled** and are fixed: `uiFont` multiplies by the scale,
so their text grew while the box around it — width 340, minimum height 44,
corner radius 8, insets 12 and 16 — stayed in fixed points. Every one of those
goes through `Theme.scaled` now.

**The capsule has no unscaled numbers.** `TitlebarCapsule` puts all of its
metrics through `Theme.current.scaled` already — padding, gap, chevron, height,
radius, chip, and every font through `uiFont`. What happens instead is that at
`--uiScale 2` in a 1100-point window it is **not drawn at all**: the title bar
comes up with the traffic lights and the overflow chevron and nothing between
them, where at 1× the same window shows `rn │ main ⇧⌘P`.

The likely reason, from reading rather than measuring, and so the first thing
to check: `minimumWidth` is `scaled(300)`, which is 600 points at 2×, and the
run control and the window's own furniture want the rest. Something decides it
does not fit and drops it. Whether that decision is the toolbar's or ours, and
whether it is a width comparison or an overflow menu, is the question.

**Worth deciding when it is understood:** what a capsule that does not fit
should do. Three shapes, and none of them is obviously right —

- **Shorten it.** Drop the branch, then the shortcut hint, then the chip, and
  keep the project name. It is the project selector; the project name is the
  part somebody is looking for.
- **Let it overflow into the `»` menu**, which is where the rest of the toolbar
  goes when the window is narrow, and is already on screen.
- **Stop scaling its minimum**. A capsule is a control, and 300 points is a
  readable width at any zoom — the *contents* need to scale, the floor for how
  narrow it may become arguably does not.

The third is a one-line change and may be all of it. The first is what somebody
would want if they were watching.

**Where to look:** `Sources/AbydosApp/Titlebar/TitlebarCapsule.swift`, and
whatever lays out the titlebar accessory around it. Reproduce with

    build/Abydos.app/Contents/MacOS/Abydos -uiScale 2 \
        --window-size 1100x400 --open <a git project> --screenshot out.png --delay 3

and the same without `-uiScale`, which is where it is still there.

---

Its number is where it sits in the queue, not what it is worth doing next.
