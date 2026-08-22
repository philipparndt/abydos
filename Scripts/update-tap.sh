#!/bin/bash
# Points the Homebrew tap at a release that already exists.
#
# The cask is three facts — a version, a checksum and a URL — and all three come
# from the release that was just published, which is why this runs after it
# rather than beside it. A tap updated first advertises a download that is not
# there yet, and `brew install` does not wait.
#
# Usage: Scripts/update-tap.sh <version> [sha256]
#        Scripts/update-tap.sh --print <version> [sha256]
#
# `--print` writes the cask to stdout and touches nothing, which is how to see
# what a release would publish without publishing it.
#
# The checksum is read from build/Abydos-<version>.dmg.sha256 when it is not
# given, so the normal path passes nothing and cannot mistype it.
set -euo pipefail

cd "$(dirname "$0")/.."

PRINT=""
if [ "${1:-}" = "--print" ]; then PRINT=1; shift; fi

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: update-tap.sh <version> [sha256]"; exit 2; }
VERSION="${VERSION#v}"
SHA="${2:-}"

REPO="${ABYDOS_REPO:-philipparndt/abydos}"
TAP="${ABYDOS_TAP:-philipparndt/homebrew-abydos}"
DMG="build/Abydos-$VERSION.dmg"

if [ -z "$SHA" ]; then
	test -f "$DMG.sha256" || { echo "no $DMG.sha256 and no checksum given"; exit 1; }
	SHA=$(awk '{print $1}' < "$DMG.sha256")
fi
# 64 hex characters or it is not a SHA-256, and a cask with a wrong one fails on
# somebody else's machine rather than on this one.
[[ "$SHA" =~ ^[0-9a-f]{64}$ ]] || { echo "not a sha256: $SHA"; exit 1; }

[ -n "$PRINT" ] || command -v gh >/dev/null \
	|| { echo "gh is not installed — brew install gh"; exit 1; }

# The tap, in a temporary clone. Nothing here belongs in this repository: a tap
# is somebody's *other* repository, and keeping a checkout of it around is how
# it comes to be edited by hand and then overwritten by this.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
CASK="$WORK/abydos.rb"

# The token is lowercase because Homebrew requires it; the app inside the image
# is `Abydos.app` and the image is `Abydos-<version>.dmg`, so neither follows
# from the other and both are spelled out.
#
# **The zap paths are `de.rnd7.ideai`, which is not a typo.** That is the
# identifier this app ships under — `release.sh` refuses to notarise a build
# carrying any other — and it kept the name the project had before it was
# Abydos. A cask that zapped `de.rnd7.abydos` would tidy away nothing and leave
# every real file behind.
cat > "$CASK" <<RUBY
cask "abydos" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/Abydos-#{version}.dmg"
  name "Abydos"
  desc "Terminal-first IDE for AI and cloud development"
  homepage "https://github.com/$REPO"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Abydos.app"

  zap trash: [
    "~/Library/Application Support/de.rnd7.ideai",
    "~/Library/Preferences/de.rnd7.ideai.plist",
    "~/Library/Saved Application State/de.rnd7.ideai.savedState",
  ]
end
RUBY

# What brew itself thinks of it, before anybody installs it. Advisory: `audit`
# reaches the network and a tap that cannot be audited from here is still a tap
# that installs.
if command -v brew >/dev/null; then
	echo "==> brew style"
	brew style "$CASK" || echo "    (style complained — look, but not fatal)"
fi

if [ -n "$PRINT" ]; then
	cat "$CASK"
	exit 0
fi

echo "==> Cloning $TAP"
gh repo clone "$TAP" "$WORK/tap" -- --quiet
mkdir -p "$WORK/tap/Casks"
cp "$CASK" "$WORK/tap/Casks/abydos.rb"

cd "$WORK/tap"
# `status`, not `diff`: a tap that has never had a cask in it is an *empty*
# repository, the file is untracked, and `git diff` — which compares what is
# tracked — says nothing has changed. It would report "already points at" and
# push nothing, on the one release where the tap most needs writing.
if [ -z "$(git status --porcelain -- Casks/abydos.rb)" ]; then
	echo "==> $TAP already points at $VERSION"
	exit 0
fi
git add Casks/abydos.rb
git commit -q -m "Abydos $VERSION"
git push -q origin HEAD
echo "==> $TAP now installs Abydos $VERSION"
echo "    brew install --cask $TAP/abydos"
