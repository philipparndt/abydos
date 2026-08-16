# 505. ⌫ marks a result done, the way ␣ does

> the usages view … does not support mark as done using the backspace key.
> Change this

⌫ does nothing in a usages or search list. ␣ marks the selection done —
`handleTableKey` in `ResultChecklist.swift` takes key code 49 and calls
`setDone`; 51 has no case and falls through. Fingers coming from IntelliJ,
where ⌫ is what takes a usage off the list, press it and nothing happens.

Both keys, in both lists. ␣ keeps working exactly as it does, and the two lists
stay the same list — `spec/usages.md` says a usages list is the same checklist
search is, and a key that worked in one and not the other would be the surprise.

## The requirement this changes, and the part of it that must not change

`spec/search.md` says, deliberately:

> The key is ␣, which ticks a checkbox everywhere in the system and destroys
> nothing anywhere. **⌫ and ⌘⌫ are not bound in the results list and do nothing
> at all there.**

with a scenario named *the key that trashes a file one pane over*. That
scenario presses **⌘⌫**, not ⌫ — and ⌘⌫ is the destructive one: in the
navigator, `ProjectNavigatorViewController.swift:2009` acts on key code 51
**only when `.command` is held**. Bare ⌫ moves nothing to the trash anywhere in
this app.

So the sentence needs narrowing and the scenario does not: **⌘⌫ stays unbound
and inert**, and only ⌫ gains a meaning. `handleTableKey` already computes
`bare` as "no ⌘, ⌥ or ⌃", so guarding the new case with it keeps ⌘⌫ falling
through for free — but that is a thing to prove with a test rather than to
assert, because it is the whole of what the old scenario protects.

## Steps

- [x] ⌫ marks the selection done, in usages and in search, and ␣ still does
- [x] The rule for which presses tick lives in `AbydosKit`, where the suite can
      reach it — the window layer has no tests, and which modifiers are let
      through is the whole of the hazard
- [x] ⌘⌫ still does nothing at all in either list, with a test that says so
- [ ] Watched from outside the app: ⌫ ticks a row, ⌫ again unticks it, ⌘⌫ does
      nothing — `--usages-steps` is the existing verb for driving this list
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/search.md` and `spec/usages.md` say what the project now does —
      the ␣ sentences name a second key, and the trash scenario stays as it is
