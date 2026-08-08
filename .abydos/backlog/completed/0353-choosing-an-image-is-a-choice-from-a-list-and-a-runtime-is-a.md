# Choosing an image is a choice from a list, and a runtime is asked rather than found

`cb0da8bf5` · 2026-08-07

Typing an image name into a field is a guess: nothing there says whether it
holds the tool, whether the tool is on its entry point, or whether it reads
what this app is going to send it. The Tools page now lists the images known
to work, with who publishes them, and keeps the field for naming another —
where it says exactly what that image has to do. For PlantUML that is the
contract `-pipe` already has: run PlantUML as the entry point, take -pipe
-tpng, read the diagram on standard input, write a PNG to standard output,
and carry Graphviz for the diagrams that need it.

The list holds only images that meet it. `plantuml/plantuml-server` is the
same project's other image and is a web service — it answers HTTP and knows
nothing about `-pipe` — so listing it as known-good would be listing the exact
failure this list exists to prevent.

And the container runtime is a setting rather than whatever was found first.
A stated preference is honoured exactly, including by finding nothing:
somebody who says Docker and has none has a problem worth being told about,
not a silent substitution of the other one. Left alone it still prefers
Apple's, which needs no daemon running before it will answer.
