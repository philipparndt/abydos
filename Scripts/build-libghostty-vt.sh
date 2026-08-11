#!/bin/bash
#
# Build Vendor/ghostty-vt.xcframework from ghostty's source.
#
# libghostty-vt is the *embeddable* half of ghostty: a terminal state machine
# that owns no pty and draws nothing (`include/ghostty/vt.h`). It is not
# `libghostty` / `GhosttyKit.xcframework`, which is the macOS app's internal
# glue and says so in its own header — that one has no cell-level read and no
# kitty graphics, so it cannot sit under this terminal. See item 0474.
#
# Why a script and a committed binary rather than a package dependency: there
# is no package. libghostty-vt has no release, no tag and no Swift package; its
# version is `0.1.0-dev` and the only way to obtain one is to build it. So the
# artifact is committed, and this script is how it is reproduced from a named
# commit rather than taken on trust.
#
# Needs `zig` (Homebrew: `brew install zig`) at exactly the version in
# ghostty's build.zig.zon `minimum_zig_version`. Measured cost on an M-series
# machine, cold: 62 seconds wall, and ~350 MB of zig build cache. Nobody pays
# that unless they run this script — a normal clone just uses the artifact.
#
#     Scripts/build-libghostty-vt.sh [<commit-ish>]
#
set -euo pipefail

# The ghostty commit this artifact was built from. Bump it deliberately: the
# vt.h API says of itself that it "is not yet stable and is definitely going to
# change", so a new commit is a thing to test, not a thing to take.
GHOSTTY_COMMIT="${1:-426386b85}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/Vendor/ghostty-vt.xcframework"
work="${TMPDIR:-/tmp}/abydos-libghostty-vt"
src="$work/ghostty"

command -v zig >/dev/null || { echo "zig not found. brew install zig" >&2; exit 1; }

mkdir -p "$work"
if [ -d "$src/.git" ]; then
	git -C "$src" fetch --quiet origin
else
	git clone --filter=blob:none https://github.com/ghostty-org/ghostty.git "$src"
fi
git -C "$src" checkout --quiet --detach "$GHOSTTY_COMMIT"
echo "ghostty at $(git -C "$src" rev-parse --short HEAD)"

# -Demit-lib-vt=true is what selects the embeddable library: it turns off the
# macOS app, the internal xcframework and the docs, and builds vt.h's library
# on its own.
( cd "$src" && zig build -Demit-lib-vt=true -Doptimize=ReleaseFast )

# The build emits a universal xcframework with iOS slices as well. Keep only
# macOS — the iOS ones are 17 MB this app can never load.
macos="$src/zig-out/lib/ghostty-vt.xcframework/macos-arm64_x86_64"
rm -rf "$out"
xcrun xcodebuild -create-xcframework \
	-library "$macos/libghostty-vt.a" \
	-headers "$macos/Headers" \
	-output "$out"

echo "wrote $out ($(du -sh "$out" | cut -f1)) from ghostty $GHOSTTY_COMMIT"
