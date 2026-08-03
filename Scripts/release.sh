#!/bin/bash
# Signs, notarises and packages the app for people who are not on this machine.
#
# Developer ID rather than the App Store: the sandbox the store requires
# redirects HOME into a container and confines every child process, and this
# app is mostly children — a login shell in a pty, git, tmux, kubectl, helm.
# A notarised Developer ID build is what every comparable editor ships.
#
# The credentials are the keychain profile the other apps here already use —
# `notarytool`, the same one GoProfiler and MQTT Analyzer are notarised with.
# On a machine that has none, once, interactively:
#
#   xcrun notarytool store-credentials notarytool \
#       --apple-id <Apple ID> --team-id 643R6YSRER --password <app-specific>
set -euo pipefail

APP="build/ideai.app"
PROFILE="${NOTARY_PROFILE:-notarytool}"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"

test -d "$APP" || { echo "no $APP — run make build first"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/ideai-$VERSION.dmg"

# --- Sign ------------------------------------------------------------------
#
# Inside out, and without `--deep`: Apple deprecated it, and it signs nested
# code with the *outer* options, which is how a bundle ends up notarised on
# the outside and rejected on the inside.
#
# The .bundle directories SwiftPM produces hold resources and no code at all;
# codesign refuses them ("bundle format unrecognized") and is right to — they
# are sealed as resources of the app that contains them. Only nested things
# with a binary inside are signed here.
echo "==> Signing with: $IDENTITY"
while IFS= read -r -d '' nested; do
	if [ -d "$nested" ] && [ ! -d "$nested/Contents/MacOS" ] && [ ! -d "$nested/Versions" ]; then
		continue
	fi
	codesign --force --timestamp --options runtime --sign "$IDENTITY" "$nested"
	echo "    signed $(basename "$nested")"
done < <(find "$APP/Contents" \
	\( -name "*.framework" -o -name "*.xpc" -o -name "*.bundle" \) -type d -print0
	find "$APP/Contents" \( -name "*.dylib" -o -name "*.so" \) -type f -print0)

codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# --- Package ---------------------------------------------------------------
#
# The disk image is what is notarised and what people download: notarising the
# .app alone leaves the ticket nowhere to be stapled for the thing that
# actually crosses the network.
echo "==> Making $DMG"
rm -f "$DMG"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "ideai" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

# --- Notarise --------------------------------------------------------------
echo "==> Notarising (this waits for Apple)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

# Stapled so it opens on a machine that is offline, or behind a captive
# portal, where Gatekeeper cannot ask Apple about it.
xcrun stapler staple "$DMG"
xcrun stapler staple "$APP"

# --- Prove it ---------------------------------------------------------------
#
# What Gatekeeper itself will say, rather than what the build hopes.
echo "==> Gatekeeper:"
spctl --assess --type open --context context:primary-signature -vv "$DMG"
spctl --assess --type execute -vv "$APP"

echo "==> Done: $DMG"
