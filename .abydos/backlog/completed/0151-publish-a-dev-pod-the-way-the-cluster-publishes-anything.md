# Publish a dev pod the way the cluster publishes anything

`649b3bde6` · 2026-08-01

Three kinds of routing object, chosen from what the cluster actually has
rather than asked for: a Gateway API HTTPRoute where a parent gateway is
named, Traefik's own IngressRoute where its CRDs are installed, and a
plain Ingress otherwise. A route with no parent gateway routes nothing,
which is why naming one is what selects that branch; `ingress.mode`
overrides the lot.

Off unless asked. A development pod that puts itself on a hostname by
accident is worse than one you have to ask to publish — and if the point
is to take over an existing hostname, the labels already do that without
another route existing at all.
