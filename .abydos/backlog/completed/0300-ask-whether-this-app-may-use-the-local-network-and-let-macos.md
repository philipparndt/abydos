# Ask whether this app may use the local network, and let macOS answer

`1a5dd9ab3` · 2026-08-05

A program launched from here could not reach an MQTT broker on the LAN: "dial
tcp 10.10.1.3:1883: connect: no route to host". The same binary run from
Terminal.app reached it. macOS gates the local network per application, and
everything an app launches inherits its answer — so a debugger, a test run, or
the program under test is denied for a permission that belongs to the app and
that none of them can ask for. What they see is EHOSTUNREACH, which reads as a
network fault and points nowhere near a privacy setting.

`--probe-lan host:port` asks directly, from the app's own process. It tells a
broker that is down (refused, or no answer) from a permission that was never
granted (unreachable, immediately) — and, because only the app can raise that
prompt, attempting it is what makes macOS offer the grant that everything
afterwards inherits.

Two things this cost, worth writing down. `nc` and the other tools in
/usr/bin are Apple-signed and not subject to the gate, so testing with them
proves nothing. And a terminal inside this app attaches to a tmux server that
was started elsewhere, so commands typed there are that server's children and
inherit its permission rather than this app's.
