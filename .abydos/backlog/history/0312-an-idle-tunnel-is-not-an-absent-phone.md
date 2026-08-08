# An idle tunnel is not an absent phone

`a0c8e00f3` · 2026-08-06

A device paired over Wi-Fi was shown as "not reachable" and runs to it were
refused, on the strength of `devicectl`'s tunnelState. That state is not
reachability: the tunnel is raised when something needs it and dropped when
idle, so a phone lying on the desk reads `disconnected` nearly always —
sampled three times in a row here, thirty seconds after a successful run to
that same phone.

So the label is the transport and nothing more, "p.iphone — Wi-Fi", and
nothing is refused for it: whether a device can be reached is known by trying,
and the run is the trying. The tunnel still breaks ties, since a device on a
cable is certainly there, and the attachments are re-read whenever the
destinations are asked for — they were cached with the destinations, which is
how a menu came to describe where a phone was twenty minutes ago.

Also: the gutter menu said "Run go run app". A Go configuration is named
after what it does, so putting the name after a verb stutters and gets worse
with every source that names configurations after a command line. The name is
the heading now, and the items are Run and Debug.
