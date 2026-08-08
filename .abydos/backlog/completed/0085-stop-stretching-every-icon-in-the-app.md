# Stop stretching every icon in the app

`7732a81c9` · 2026-08-01

SF Symbols are not square. A folder is wider than it is tall, a chevron wider
still, a document taller than wide. Every symbol in the app was drawn into a
square box and stretched to fill it — which is why the tool strip's icons
looked squeezed and the panel's chevron read as a letter v rather than a
chevron.

One helper draws a symbol centred in its slot at its own proportions, and all
seventeen places that drew one now use it. The tree had a private copy of the
same fix from earlier today; it uses the shared one now.
