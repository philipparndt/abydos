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

APP="build/Abydos.app"
PROFILE="${NOTARY_PROFILE:-notarytool}"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"

test -d "$APP" || { echo "no $APP — run make build first"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/Abydos-$VERSION.dmg"

# The identifier the app ships under, checked rather than assumed. `BUNDLE_ID`
# exists so a local build can carry the identifier this app used to have, and
# an exported one would otherwise reach this build too — releasing under a name
# that is not the app's, which every grant, receipt and update on a user's
# machine is keyed to. Cheaper to refuse than to explain afterwards.
SHIPPING_ID="de.rnd7.ideai"
BUILT_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")
if [ "$BUILT_ID" != "$SHIPPING_ID" ]; then
	echo "refusing to release: $APP is $BUILT_ID, not $SHIPPING_ID" >&2
	echo "  rebuild without BUNDLE_ID set: unset BUNDLE_ID && make build" >&2
	exit 1
fi

# And that this build's UUID is its own. `PIN_UUID` exists so a local build
# keeps the Local Network grant that is filed against a particular UUID, and a
# release carrying a borrowed one is a release whose crash reports cannot say
# which build they came from. `make release` builds with PIN_UUID=0; this is for
# the times somebody runs the two steps by hand.
PINNED="C94373A9-FCB2-3966-B045-208B26A4CA30"
BUILT_UUID=$(dwarfdump --uuid "$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Contents/Info.plist")" 2>/dev/null | awk '{print $2}')
if [ "$BUILT_UUID" = "$PINNED" ]; then
	echo "refusing to release: the executable carries the pinned development UUID" >&2
	echo "  rebuild without it: make build PIN_UUID=0" >&2
	exit 1
fi

# And that it runs on both processors. The download is the one build whose
# machine is not known in advance, and 0.20.0 went out with notes promising an
# Intel build over an image that carried none: the universal build had been
# taught to `make release` and the publish script builds on its own. The bundle
# printed `architectures: arm64` and nobody read it, so it is a stop now. Every
# executable in the bundle, not only the app — the hook, the bench and the
# backlog tool ship inside it and would be the ones to fail on the other Mac.
for binary in "$APP/Contents/MacOS/"* "$APP/Contents/Resources/bin/"*; do
	[ -f "$binary" ] || continue
	# Scripts in Resources/bin are not Mach-O and have no architecture to ask for.
	file -b "$binary" | grep -q "Mach-O" || continue
	ARCHS_FOUND=$(lipo -archs "$binary" 2>/dev/null || true)
	# Each architecture on its own. `lipo` lists them in the order the file
	# holds them, and the first version of this asked for both in one pattern
	# whose two spaces could not share the one between the words — so it
	# refused the very build it was written to accept, `x86_64 arm64`, at the
	# first 0.20.1 attempt, after the tag was made.
	for wanted in arm64 x86_64; do
		case " $ARCHS_FOUND " in
			*" $wanted "*) ;;
			*)
				echo "refusing to release: $(basename "$binary") is built for '$ARCHS_FOUND', which lacks $wanted" >&2
				echo "  rebuild universal: make build PIN_UUID=0 ARCHS=\"arm64 x86_64\"" >&2
				exit 1
				;;
		esac
	done
done

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
#
# `Contents/MacOS` is in that list for a reason that cost a notarisation: this
# app ships a second executable there, `abydos-hook`, and it is not a framework,
# an xpc service, a bundle, a dylib or a .so. Signing the app around it seals
# it as it is rather than re-signing it, so it kept the ad-hoc signature the
# bundler gave it and Apple rejected the archive with three errors about one
# file. Every Mach-O in the bundle has to be signed, whatever it is called.
MAIN=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Contents/Info.plist")

echo "==> Signing with: $IDENTITY"
while IFS= read -r -d '' nested; do
	if [ -d "$nested" ] && [ ! -d "$nested/Contents/MacOS" ] && [ ! -d "$nested/Versions" ]; then
		continue
	fi
	codesign --force --timestamp --options runtime --sign "$IDENTITY" "$nested"
	echo "    signed $(basename "$nested")"
done < <(find "$APP/Contents" \
	\( -name "*.framework" -o -name "*.xpc" -o -name "*.bundle" \) -type d -print0
	# Every Mach-O in the bundle, wherever it is and whatever it is called —
	# which is what the paragraph above says and what this used to only half do.
	# It looked in `Contents/MacOS`, and the command-line tools live in
	# `Contents/Resources/bin`: `abydos-backlog` and `abydos-bench` went out
	# unsigned, the check below caught them, and cutting 0.2.0 stopped after the
	# tag was already made. Asking the file what it is costs one `file` per
	# executable and cannot go stale when the next tool is added.
	#
	# `.dylib` and `.so` are covered by this too, since they are Mach-O; the
	# scripts in `bin` are not and are correctly left to be sealed as resources.
	while IFS= read -r -d '' candidate; do
		[ "$candidate" = "$APP/Contents/MacOS/$MAIN" ] && continue
		file -b "$candidate" | grep -q "Mach-O" && printf '%s\0' "$candidate"
	done < <(find "$APP/Contents" -type f -perm -111 -print0))

codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# --- Check before Apple does ------------------------------------------------
#
# Notarisation takes minutes and answers "Invalid" with a submission id, and
# the reason is in a log you have to go and ask for. Every one of those errors
# is visible here in a second: a Mach-O that is not signed by a Developer ID,
# or is signed without the hardened runtime, is one Apple will reject.
echo "==> Checking every Mach-O before uploading"
FAILED=0
while IFS= read -r -d '' binary; do
	file "$binary" | grep -q "Mach-O" || continue
	DETAILS=$(codesign -dvv "$binary" 2>&1)
	if ! grep -q "Authority=Developer ID Application" <<< "$DETAILS"; then
		echo "    NOT signed with a Developer ID: ${binary#"$APP/"}"
		FAILED=1
	elif ! grep -q "flags=.*runtime" <<< "$DETAILS"; then
		echo "    no hardened runtime: ${binary#"$APP/"}"
		FAILED=1
	fi
done < <(find "$APP/Contents" -type f -perm -111 -print0)

if [ "$FAILED" -ne 0 ]; then
	echo "Stopping: Apple would reject this, and would take several minutes to say so."
	exit 1
fi
echo "    every executable is signed and hardened"

# --- Notarise the app ------------------------------------------------------
#
# The app is notarised and stapled *before* it is packaged, so that the ticket
# travels inside the bundle a user drags out of the image. Stapling the image
# does not staple what is in it. An app that leaves here without its own ticket
# makes Gatekeeper ask Apple over the network on first launch, and a machine
# that is offline, behind a captive portal or a filtering proxy gets no verdict
# back — which macOS reports to the user as "could not verify" that the app is
# "free of malware", for the app and for every helper it spawns.
echo "==> Notarising the app (this waits for Apple)"
ditto -c -k --keepParent "$APP" "$APP.zip"
xcrun notarytool submit "$APP.zip" --keychain-profile "$PROFILE" --wait
rm -f "$APP.zip"
xcrun stapler staple "$APP"

# --- Package ---------------------------------------------------------------
#
# The disk image is notarised as well: it is the thing that actually crosses
# the network, and it needs a ticket of its own for Gatekeeper to admit it
# before anything has been copied out of it.
echo "==> Making $DMG"
rm -f "$DMG"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Abydos" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

# --- Notarise the image ----------------------------------------------------
echo "==> Notarising the disk image (this waits for Apple)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

# Stapled so it opens on a machine that is offline, or behind a captive
# portal, where Gatekeeper cannot ask Apple about it.
xcrun stapler staple "$DMG"

# --- Prove it ---------------------------------------------------------------
#
# What Gatekeeper itself will say, rather than what the build hopes.
#
# The tickets are checked because their absence is invisible to everything
# else here: an image packaged before the app was stapled still signs, still
# notarises, and still passes both `spctl` lines below.
echo "==> Tickets:"
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG"

# And the one that actually went wrong once — the app *inside* the image, which
# is the copy a user drags to /Applications and the only one whose ticket they
# ever depend on.
MOUNT=$(mktemp -d)
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG"
if xcrun stapler validate "$MOUNT/Abydos.app"; then STAPLED=0; else STAPLED=1; fi
hdiutil detach -quiet "$MOUNT" || true
rmdir "$MOUNT" 2>/dev/null || true
if [ "$STAPLED" -ne 0 ]; then
	echo "Stopping: the app inside $DMG carries no ticket, so it will ask Apple"
	echo "on first launch and be refused on any machine that cannot reach them."
	exit 1
fi

echo "==> Gatekeeper:"
spctl --assess --type open --context context:primary-signature -vv "$DMG"
spctl --assess --type execute -vv "$APP"

echo "==> Done: $DMG"
