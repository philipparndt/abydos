## 1. The arithmetic (AbydosKit)

- [x] 1.1 `PanelRowSnap.State` carries the divider thickness and `dividerPosition` returns `total - wanted - thickness`, so the panel ends up the height that was asked for
- [x] 1.2 `PanelRowSnapTests`: the idempotence case — apply the answer, recompute the state it produces, and the second answer is nil; the test that asserted the old arithmetic is corrected rather than left standing

## 2. The handler (AbydosApp)

- [x] 2.1 `splitViewDidResizeSubviews` remembers the split and panel heights it last acted on and returns early when neither moved
- [x] 2.2 The three other `total - height` divider computations — putting the panel away and back, making room for the editor, maximising it — carry the thickness too

## 3. Proving it

- [x] 3.1 A driven run: the panel's height reported, the window made wider, the height reported again — the same number
- [x] 3.2 A driven run showing the rounding still happens where it should: a height that is not whole rows is rounded once and then left alone

## 4. Before finishing

- [x] 4.1 `make test` clean, `make warnings` clean, machine load said if a bound flakes
- [x] 4.2 No spec is made untrue: the terminal delta adds beside the panel requirements already standing
