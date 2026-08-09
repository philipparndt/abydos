# 418. The capsule keeps a 1× box around 2× type

-> it is not missing, when there is not enough space it is moved to a hamburger menu.
-> the text is scaled, but not the box arround. The pill is getting slimer instead of higher

The title this entry was filed under said the capsule went missing at a large
zoom. It does leave the titlebar in a narrow window at 2×, and that is the
overflow menu doing its job, not a fault. What is a fault is the shape it keeps
when it is there: every font goes through `uiFont` and doubles, the box around
them does not, and the pill reads as a slim strip with type too large for it.

## What was capping it

Nothing in `TitlebarCapsule`. Every metric in it, height included, already goes
through `Theme.current.scaled`. The cap is AppKit's: the capsule is the view of
an `NSToolbarItem`, and a toolbar sizes a view-based item to 28 points and reads
nothing of what its `intrinsicContentSize` asks for. Measured in the window at
both zooms, from `reportToolbarForTesting`:

    1×:  capsule frame h=28   intrinsic h=30   row (NSTitlebarView) h=52
    2×:  capsule frame h=28   intrinsic h=60   row (NSTitlebarView) h=52

The width *is* taken from the intrinsic size — 302 at 1×, 604 at 2× — so it is
the height alone that the toolbar decides for itself. The comment on `inset`
said as much already: "a toolbar clamps its items to the row's height whatever
they ask for", and the one-point `inset` that came with "A taller capsule" was
the last of a fixed budget being spent rather than the budget being raised.

Four things were tried against the running window before anything was changed:

- **A tall titlebar accessory** (`NSTitlebarAccessoryViewController`,
  `.trailing`, height constrained to `scaled(52)`). The row stayed 52 and the
  item stayed 28. With `.bottom` it adds a row *below* the toolbar — the
  titlebar grows, the item does not.
- **`item.minSize` / `item.maxSize`.** Nothing.
- **A height constraint on the view.** Honoured: the capsule became 60 points at
  2×. It was then drawn over the window's top edge, because the row it sits in
  is still 52 and the titlebar is the system's — it does not zoom with us.
- **`toolbarStyle = .expanded`.** The row *does* follow the item there: 66
  points at 2×, in a 94-point titlebar. It costs a second row — traffic lights
  alone on top and the capsule under them — at every zoom, including 1×, which
  is not the arrangement this titlebar is.

## Done

The capsule carries a height constraint, since that is the one part of the size
a toolbar honours, and takes the height the zoom asks for or what the row has
left, whichever is smaller — `scaled(30)` against 52 less four points of air at
each end. At 1× that is the 30 points it always wanted (28 before, so nothing
visibly moves); at 2× it is 44 rather than 28, and the pill is a field around
its type again rather than a strip behind it.

The constraint is measured from inside the row, in `viewDidMoveToSuperview` and
again in `layout()`, because the row is only measurable from within it and the
capsule is built before it is in one. `layoutTitlebarPills` pushes a zoom into
it, which is what makes ⌘+ take effect without a relaunch.

**What this does not do**, and it is the honest limit rather than an oversight:
at 2× the capsule wants 60 points and can have 44. The system titlebar is 52 at
every zoom, and the only way past it found here was `.expanded`, which changes
the titlebar at every zoom to fix it at one. If the 44 ever reads as short, that
trade is where to start.

---

Its number is where it sits in the queue, not what it is worth doing next.
