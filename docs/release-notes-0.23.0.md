# Abydos 0.23.0

## HTML files have a preview

An `.html`, `.htm` or `.xhtml` now has the same Source, Preview, Split Right
and Split Down as a markdown file, and the pane shows the page the document
makes. It opens as text and the preview is asked for once, then remembered.
What is rendered is the buffer, so unsaved edits are on screen, and the
stylesheets, scripts and pictures beside the file load as they do in a browser.

Two rules the pane keeps. **Nothing is fetched**: a reference to a remote
address is refused whether it is a stylesheet, a script or a pixel, and the
pane says how many the document asked for and names the first. **A page's own
scripts run only in a trusted project**, because a `<script>` is the project's
code; an untrusted project renders the markup and says so.

A link to a remote address opens in the browser and a link to a file beside it
opens that file in a tab. The pane itself never navigates away from the
document the tab names.

## Toggle Preview is no longer only markdown

⇧⌘V was *Toggle Markdown Preview* and did nothing in a `.puml`, a `.scad` or a
`.mmd`, although all three have the control in the tab bar. It is *Toggle
Preview* now and works in any file that has both a source and a rendered form.
