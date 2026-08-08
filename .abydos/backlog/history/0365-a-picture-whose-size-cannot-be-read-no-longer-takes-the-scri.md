# A picture whose size cannot be read no longer takes the script down

`dcfc16045` · 2026-08-07

`set -e` and a division by a width of zero: the fallback for a height,
reached when the cell size is unknown, divided by the picture's own width
— which is zero when `sips` cannot read the file. The script exited
before writing a byte. The previous commit shipped with its own tests
failing, which is on me: I read the grep that summarised them rather than
the result.
