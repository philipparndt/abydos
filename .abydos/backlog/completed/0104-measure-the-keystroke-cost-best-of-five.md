# Measure the keystroke cost best-of-five

`9ca7cebfe` · 2026-08-01

The threshold caught a 2.07ms keystroke against a 2ms budget, but the same
measurement alone on an idle machine is 0.6ms: the rest of the suite runs
alongside it, and a busy machine moves this number by three times or more.
That is far more than any regression worth catching, so the test was
reporting load rather than code.

Best of five rounds now, which is what the terminal benchmarks already do
and for the same reason.
