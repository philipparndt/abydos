# Ship with Developer ID rather than through the App Store

`828fe0cf9` · 2026-08-03

The upload failed on the sandbox, and rightly: the store requires
com.apple.security.app-sandbox, which redirects HOME into a container and
confines every child process — and this app is mostly children. A login
shell with somebody's own dotfiles, tmux attaching to a server that is
already running, git pushing with the keys in ~/.ssh, kubectl reading
~/.kube/config: none of that survives it, and the entitlements that would
grant them back are not ones review hands out. So: Developer ID and
notarisation, which is what every comparable editor ships.

`make release` signs inside out with the hardened runtime and a secure
timestamp, packages a DMG, submits it to Apple, staples both, and then
asks Gatekeeper what it thinks rather than assuming. `make sign-check`
says whether the certificate and the notary profile are in place.

The two other complaints from the upload were plain plist gaps and are
fixed either way: LSApplicationCategoryType, and LSHandlerRank on the
folder document type.
