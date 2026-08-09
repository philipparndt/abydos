# 417. The destination menu is seventy-five simulators and no Mac

Reported while running a real project — `wall-display2`, an iOS app with a Mac
Catalyst destination. Two faults, and they turn out to be unrelated.

Asked of that project's scheme, `xcodebuild -showdestinations` answers with 79
eligible destinations:

    simulators                 75   (23 distinct models × their runtimes)
    real devices                2
    macOS                       2   (both Mac Catalyst)
    placeholders ("Any …")      3

## Why there is no Mac

Not a filter on platform — the parse drops it on purpose, for a different case.
Both macOS lines carry a variant:

    { platform:macOS, arch:arm64, variant:Mac Catalyst, id:…, name:My Mac }
    { platform:macOS, variant:Mac Catalyst, name:Any Mac }

and `XcodeDestination.parse` has

    guard fields["variant"] == nil else { continue }

written for "Designed for [iPad,iPhone]", which genuinely is ambiguous: it is an
iOS build running on this Mac, it has a different product directory from the
macOS one, and the name alone does not say which it is. Mac Catalyst was
swept up with it, and Mac Catalyst is neither ambiguous nor unrunnable — it
says what it is in the variant.

**It cannot simply be let through, though**, and this is the part worth knowing
before starting: `productDirectorySuffix` has no case for it. A Catalyst build
lands in `Build/Products/<configuration>-maccatalyst`, and that switch returns
`""` for `platform:macOS`, so the run would look in the wrong directory and
report a missing product. Both halves or neither.

`-destination` also needs the variant passed through — `platform=macOS,variant=Mac
Catalyst,id=…` — or `xcodebuild` picks whichever macOS destination it likes.

## Why there are seventy-five simulators

Because there are: 23 models against every installed runtime, and the ineligible
ones are already dropped. The list is not wrong, it is just not a menu — a
scrolling column that runs off the screen is not somewhere anybody picks
something.

## Decided, and done

**Devices are the menu; simulators are a dialog.** Both halves are in, with
`XcodeDestinationMenu` in AbydosKit holding the rules so they are testable
without a menu, and `DestinationPicker` as the panel.

The Mac is back: `parse` lets `variant:Mac Catalyst` through while still
dropping "Designed for [iPad,iPhone]", `productDirectorySuffix` answers
`-maccatalyst`, and `-destination` now carries the variant — an id alone let
`xcodebuild` choose between two macOS destinations that share it.

- **Real devices, directly in the menu**, as now — there are two, and they are
  the ones somebody picks by name. This Mac too, once the above is fixed.
- **The latest of each family, directly** — one iPhone, one iPad, one Apple TV,
  one Watch, one Vision, each at the newest runtime that model has installed.
  That is the shortcut that covers the ordinary case, and it is five lines
  rather than seventy-five.
- **"Other simulators…" opens a dialog with a filter.** Typing narrows it; the
  whole list is reachable; nothing is hidden. A menu cannot have a filter field,
  which is the actual reason this cannot stay a menu.

## The three that were left, now decided

- **"Latest" needs a rule, not a sort.** Runtimes compare as numbers already
  (9.0 against 10.0 is why), but a model present in one runtime and absent from
  another is not a comparison at all. Pick the newest *runtime* the model itself
  has, rather than the newest runtime installed — a model that stopped shipping
  should offer its last version, not disappear because something newer exists
  without it.
- **The picker remembers per project.** Less state, and it is what somebody means
  by "the simulator I use". A project with an app and a watch app shares one
  choice, which is the cost, and it is small next to remembering a stale scheme's
  preference for ever.
- **The placeholders stay out.** "Any iOS Device" names a family rather than a
  machine, and installing on one is not a thing. Nobody has missed them.

---

Its number is where it sits in the queue, not what it is worth doing next.
