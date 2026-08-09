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

## Decided

**Devices are the menu; simulators are a dialog.**

- **Real devices, directly in the menu**, as now — there are two, and they are
  the ones somebody picks by name. This Mac too, once the above is fixed.
- **The latest of each family, directly** — one iPhone, one iPad, one Apple TV,
  one Watch, one Vision, each at the newest runtime that model has installed.
  That is the shortcut that covers the ordinary case, and it is five lines
  rather than seventy-five.
- **"Other simulators…" opens a dialog with a filter.** Typing narrows it; the
  whole list is reachable; nothing is hidden. A menu cannot have a filter field,
  which is the actual reason this cannot stay a menu.

**Worth deciding, and not decided yet:**

- What "latest" means when a model has runtimes that are not comparable — 26.5
  and 27.0 are, but a model present in one runtime and absent from another needs
  a rule rather than a sort.
- Whether the dialog remembers what was last chosen per project, or per scheme.
  Per scheme is more precise and is more state; per project is what somebody
  probably means by "the simulator I use".
- Whether the placeholders ("Any iOS Device") stay out. They are dropped today
  and nothing has asked for them back, so this is a question to answer with a
  sentence, not work.

---

Its number is where it sits in the queue, not what it is worth doing next.
