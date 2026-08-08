# Follow the current context, but not onto production

`5cb99bf88` · 2026-08-02

A configuration that is shared cannot name a cluster: everybody's is
called something different. It can say `${currentContext}` and then say
which contexts that is allowed to be — `*-local, k3c-*` — and a
configuration that follows whoever runs it stops following them the
moment they are pointed at production.

Glob rather than a regular expression: the person writing `*-local` in a
configuration file is thinking of a shell, and it should mean what it
looks like. A context named outright is checked too — writing one down is
not a way around the rule — and being refused says which context and
which patterns, since the fix is one of the two.
