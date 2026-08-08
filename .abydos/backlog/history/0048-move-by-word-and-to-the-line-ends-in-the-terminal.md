# Move by word and to the line ends in the terminal

`d80872feb` · 2026-07-31

⌥← and ⌘← did nothing. The arrow keys went straight to the emulator's
cursor encoding, which knows about the cursor-key mode but not about
modifiers, so a modified arrow was indistinguishable from a bare one.

They now send the readline movements: ⌥←/⌥→ are meta-b and meta-f, ⌘←/⌘→
are ctrl-a and ctrl-e, and ⌘⌫ is ctrl-u. That is the mapping macOS users
already have from every native text field, and it works in a shell and in
a terminal UI alike — unlike `ESC [ 1 ; 3 D`, which a program has to opt
into parsing, while meta-b has meant "back one word" for decades.

⌘ combinations are offered around as key equivalents before they arrive
as a key press, and one that nothing claims never arrives at all, so the
terminal claims exactly these three. ⌘C, ⌘V and the rest stay with the
menu.

Verified against a real shell rather than only in the abstract: two
⌥← land the cursor two words back, and ⌘← puts it at the start.
