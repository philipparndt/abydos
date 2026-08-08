# Size the tab bar's preview control to its label

`59e5b9720` · 2026-07-31

The control was a fixed 78pt whatever it said. That fits "Source" and
"Preview", but "Split Right" needs about 99pt, so the label ran over the
chevron and out through the end of the pill. It is now measured from its
contents, with the metrics shared between the measuring and the drawing so
they cannot disagree again.
