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

## Watched from outside the app

Both lists, the same four presses, driven with the launch harness — `⌫`, `⌫`
again, `⌘⌫`, `␣` — against a selection of two rows. The rows come back from the
pane itself, with the done state it believes it has, which is the half a
screenshot cannot show.

**The search list**, over two files in a scratch project, `--search needle
--search-steps "rows,select:1+3,delete-key,rows,delete-key,rows,cmd-delete-key,rows,space-key,rows"`.
Rows 1 and 3 selected, one in each file, so both headings have to move:

    SEARCH rows: 6            (after ⌫)          (after ⌫ again)   (after ⌘⌫)        (after ␣)
       0 file b.swift 0/1     0 file b.swift 1/1 DONE  0/1          0/1               1/1 DONE
      *1 match 2 print(…)    *1 match … DONE          *1 match …   *1 match …        *1 match … DONE
       2 file a.swift 0/3     2 file a.swift 1/3       0/3          0/3               1/3
      *3 match 1 let one …   *3 match … DONE          *3 match …   *3 match …        *3 match … DONE

**The usages list**, from gopls over a five-usage symbol, `--usages 25:1
--usages-steps "rows,select:1+2,delete-key,rows,delete-key,rows,cmd-delete-key,rows,space-key,rows"`:

    USAGES heading: 5 usages in 1 file window=false undo=— redo=— opened=[]
    USAGES who: …ChecklistTable
    ⌫    → 0 file main.go 2/5, rows 1 and 2 DONE
    ⌫    → 0 file main.go 0/5, neither DONE
    ⌘⌫   → 0 file main.go 0/5, unchanged — nothing marked, nothing unmarked
    ␣    → 0 file main.go 2/5, rows 1 and 2 DONE

Two things worth keeping from the driving itself. The transcript only survives
if the app's stdout is on a pty — `script -q /dev/null <the binary> …` — because
a driver run ends in a kill and block-buffered output dies with it; the same run
redirected straight to a file produced one line and then nothing. And a project
with a session saved in it is the wrong thing to drive: `--file` opened nothing
in the examples' `go-service` because that project restores a maximised
terminal, so `activeTabURL` was nil and Find Usages had no place to ask about. A
copy of the same two files in a fresh directory answered in fourteen seconds.

## Estimate

2026-08-16 17:55 — about half an hour left

## Steps

- [x] ⌫ marks the selection done, in usages and in search, and ␣ still does
- [x] The rule for which presses tick lives in `AbydosKit`, where the suite can
      reach it — the window layer has no tests, and which modifiers are let
      through is the whole of the hazard
- [x] ⌘⌫ still does nothing at all in either list, with a test that says so
- [x] Watched from outside the app: ⌫ ticks a row, ⌫ again unticks it, ⌘⌫ does
      nothing — `--usages-steps` is the existing verb for driving this list
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/search.md` and `spec/usages.md` say what the project now does —
      the ␣ sentences name a second key, and the trash scenario stays as it is
