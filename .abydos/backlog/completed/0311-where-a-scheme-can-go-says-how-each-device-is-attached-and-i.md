# Where a scheme can go says how each device is attached, and is where you look

`0cf34b7cb` · 2026-08-06

Two things were wrong with choosing a device. It could only be chosen from
the Run menu, while the control somebody presses to choose what runs is the
one in the titlebar — a device picker reachable only from a menu bar is a
device picker nobody finds. And `xcodebuild -showdestinations` offers a phone
on a cable exactly as it offers one asleep in another room, so the difference
turned up several minutes later as an install that timed out.

So the schemes are in the titlebar menu too, each with its destinations, and
`devicectl` is asked at the same time as `xcodebuild` for how each device is
reached: "p.iphone — Wi-Fi", "iPad von Philipp — Wi-Fi, not reachable". The
two tools are merged by UDID, since they disagree about identifiers —
`xcodebuild` uses the device's, `devicectl` its own, and it accepts either.

The default now prefers a device that can be reached. It landed on whichever
sorted first, which here is an iPad in another room while the phone on the
desk sits below it. And a run aimed at something unreachable says so before
the build rather than after it, with what to do about it — for a cable, that
Xcode's Devices window is where a phone is paired for Wi-Fi.

The menu harness prints what it built instead of opening it: a menu runs a
nested event loop, so a capture run is never drawn, never shot, and has to be
killed, which throws away the output that would have said what was in it.
