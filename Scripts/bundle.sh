#!/bin/bash
#
# Wraps the SPM executable into a real .app.
#
# The bundle is what gives Abydos a Dock presence, a proper unified titlebar, and
# — importantly — a `Bundle.main.resourceURL` that the grammar query bundles can
# be found under at runtime.
#
# Usage: Scripts/bundle.sh [debug|release]   (default: release)

set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Abydos.app"
CONTENTS="$APP/Contents"

echo "==> Building ($CONFIG)"
# Xcode's Swift rather than whatever is first on the PATH: a toolchain manager
# such as swiftly pins an older release, which cannot compile against a newer
# SDK and fails here with an error about Foundation rather than about Abydos.
SWIFT=(xcrun swift)

# Passed by the Makefile; empty when somebody runs this script directly.
read -ra JOB_FLAGS <<< "${SWIFT_JOBS:-}"
"${SWIFT[@]}" build "${JOB_FLAGS[@]}" -c "$CONFIG"

BIN_DIR="$("${SWIFT[@]}" build "${JOB_FLAGS[@]}" -c "$CONFIG" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_DIR/Abydos" "$CONTENTS/MacOS/Abydos"

# The Claude Code hook, which travels with the app but is its own binary:
# Claude runs it several times per tool call, and starting one that links
# AppKit and a syntax engine to read a line of JSON would be felt in every
# session on the machine.
cp "$BIN_DIR/abydos-hook" "$CONTENTS/MacOS/abydos-hook"

# The commands a shell in this app can use. Bundled rather than installed, so
# they are there for anybody who runs the app without running `make
# install-cli` — and so the copy that ships is the copy that was built.
mkdir -p "$CONTENTS/Resources/bin"
# `abydos` as well as the rest: typed in one of this app's panes it opens a file
# in the window it was typed in, and it can only do that through the escape it
# writes — which the copy in the bundle is guaranteed to have and an older one
# installed in /usr/local/bin is not.
cp Scripts/abydos "$CONTENTS/Resources/bin/abydos"
chmod +x "$CONTENTS/Resources/bin/abydos"
cp Scripts/abydos-icat "$CONTENTS/Resources/bin/abydos-icat"
chmod +x "$CONTENTS/Resources/bin/abydos-icat"

# The benchmark, under the same prefix as the rest. It is what to reach for
# when the terminal feels slow, and one that lives in a checkout behind
# `swift run` is one nobody runs — least of all against the build that is
# actually installed, which is the build the question is about.
cp "$BIN_DIR/firebench" "$CONTENTS/Resources/bin/abydos-bench"
chmod +x "$CONTENTS/Resources/bin/abydos-bench"

# The backlog, on the PATH of every shell this app opens. It has to be here
# rather than only installed: an agent working an item runs in a terminal this
# app started, and the first thing the instructions tell it to type is this.
cp "$BIN_DIR/abydos-backlog" "$CONTENTS/Resources/bin/abydos-backlog"
chmod +x "$CONTENTS/Resources/bin/abydos-backlog"

# Grammar query bundles. Without these every file opens uncoloured, so treat a
# missing set as a hard failure rather than shipping a broken app.
COUNT=0
for bundle in "$BIN_DIR"/*.bundle; do
	[ -e "$bundle" ] || continue
	cp -R "$bundle" "$CONTENTS/Resources/"
	COUNT=$((COUNT + 1))
done
if [ "$COUNT" -eq 0 ]; then
	echo "error: no resource bundles found in $BIN_DIR — grammars would not highlight" >&2
	exit 1
fi
echo "    copied $COUNT grammar bundles"

# GoSTL ships its shader as source and compiles it in its own Makefile, so a
# build that only asks SwiftPM for the library gets a bundle without the
# default.metallib the renderer looks for — and the 3D tab aborts on open.
# The shader sits at the root of the SwiftPM bundle, not under
# Contents/Resources — that layout is the one GoSTL's own installer produces.
#
# Written into the build directory's copy as well as the app's. `Bundle.module`
# resolves to the build path whenever it still exists, which it does on the
# machine that built the app, so shipping it only inside the .app leaves a
# developer running a viewer that cannot find its shaders.
#
# **And a shader that does not compile fails the build.** This block was right
# and its failure path was silence: where the Metal toolchain is not installed,
# `xcrun metal` cannot run, the `&&` chain quietly produces nothing, there is no
# `else`, and the build goes on to print `==> Done`. What ships is the bundle
# this comment was written to prevent — `Shaders.metal` present, `default.metallib`
# absent — and the app then dies at
#
#     GoSTL/MetalView.swift:80: Fatal error: Failed to initialize Metal
#     renderer: shaderLoadingFailed
#
# the first time anything opens the 3D viewer. With a `.scad` tab in the restored
# session that is one second after launch, every launch: an app nobody can start,
# from a build that reported success. The same fault as the codesign warning
# below, found the same way, and it is the third time in this file that an error
# printed instead of returned has cost a day.
GOSTL_SHADER=$(find "$CONTENTS/Resources" -name Shaders.metal -path "*GoSTL*" 2>/dev/null | head -1)
if [ -n "$GOSTL_SHADER" ]; then
	if ! SHADER_OUT=$(xcrun -sdk macosx metal -c "$GOSTL_SHADER" -o "$BIN_DIR/Shaders.air" 2>&1) \
		|| ! SHADER_OUT=$(xcrun -sdk macosx metallib "$BIN_DIR/Shaders.air" -o "$BIN_DIR/default.metallib" 2>&1)
	then
		# The heading is decided by the case below, because the two failures mean
		# opposite things now: one is a note about this machine, the other is a
		# broken shader.
		case "$SHADER_OUT" in
			*"Metal Toolchain"*)
				echo "    note: the Metal toolchain is not installed here, so the 3D" >&2
				echo "    viewer's shaders were not compiled ahead of time:" >&2
				;;
			*)
				echo "    error: the 3D viewer's shaders did not compile:" >&2
				;;
		esac
		echo "$SHADER_OUT" | sed 's/^/    /' >&2
		# **A missing toolchain and a broken shader are no longer the same
		# thing.** Since gostl 0.23.2 the renderer falls back to compiling the
		# `Shaders.metal` that ships in its bundle, which needs no toolchain — so
		# a machine without one builds an app whose viewer works, and failing the
		# build there would be refusing to build over nothing.
		#
		# A shader that does not *compile* is still fatal, because the runtime
		# fallback compiles the same source and would fail the same way — later,
		# and in front of somebody trying to look at a model.
		case "$SHADER_OUT" in
			*"Metal Toolchain"*)
				echo "    Install it with: xcodebuild -downloadComponent MetalToolchain" >&2
				echo "    Carrying on: the viewer compiles this source at runtime instead," >&2
				echo "    so the only cost is a few hundred milliseconds the first time a" >&2
				echo "    model is opened." >&2
				;;
			*)
				# The escape hatch stays for the case it was written for: a
				# shader this build cannot compile at all. The alternative to a
				# broken 3D viewer should not be no build.
				if [ "${ALLOW_MISSING_SHADERS:-0}" = "1" ]; then
					echo "    ALLOW_MISSING_SHADERS=1: carrying on without them." >&2
				else
					exit 1
				fi
				;;
		esac
	else
		echo "    compiled the 3D viewer's shaders"
	fi

	if [ -f "$BIN_DIR/default.metallib" ]; then
		# Asked of the result rather than assumed from an exit code, because what
		# the renderer looks for is a file at a path and nothing else will do.
		find "$CONTENTS/Resources" "$BIN_DIR" -type d -name "GoSTL_GoSTL.bundle" 2>/dev/null |
			while read -r target; do
				cp "$BIN_DIR/default.metallib" "$target/"
			done

		if [ ! -f "$CONTENTS/Resources/GoSTL_GoSTL.bundle/default.metallib" ]; then
			echo "    error: the shaders compiled but did not reach the app bundle" >&2
			exit 1
		fi
	fi
fi

# Bundled fonts, registered at launch so powerline prompts render without the
# user installing anything.
if [ -d Resources/Fonts ]; then
	mkdir -p "$CONTENTS/Resources/Fonts"
	cp Resources/Fonts/*.ttf "$CONTENTS/Resources/Fonts/" 2>/dev/null || true
	cp Resources/Fonts/LICENSE-* "$CONTENTS/Resources/Fonts/" 2>/dev/null || true
fi

# The Dockerfiles for tools that are built on the machine rather than pulled.
# They have to travel with the app: `ToolImageRecipes` looks under the bundle's
# resources first and only then in a checkout, and an installed app that cannot
# find them offers no build-here option at all — a feature that silently is not
# there, which is worse than one that fails.
#
# Copied whole, and the fingerprint that names the built image is taken over the
# directory with paths relative to it, so the copy in the bundle and the copy in
# the source tree name the same image and nobody builds twice.
if [ -d ToolImages ]; then
	rm -rf "$CONTENTS/Resources/ToolImages"
	cp -R ToolImages "$CONTENTS/Resources/ToolImages"
	echo "    bundled $(find ToolImages -name Dockerfile | wc -l | tr -d ' ') tool image recipes"
fi

# The icon. Generated by Scripts/make-icon.py; regenerate after editing that.
if [ -f Resources/Icon/Abydos.icns ]; then
	cp Resources/Icon/Abydos.icns "$CONTENTS/Resources/"
else
	echo "    WARNING: no icon — run python3 Scripts/make-icon.py"
fi

# Third-party notices travel with the app, not just the repo.
if [ -f THIRD-PARTY-NOTICES.md ]; then
	cp THIRD-PARTY-NOTICES.md "$CONTENTS/Resources/" 
	echo "    bundled $(ls "$CONTENTS/Resources/Fonts"/*.ttf 2>/dev/null | wc -l | tr -d ' ') fonts"
fi

# The same Info.plist Xcode builds with, rather than a second copy of it that
# drifts: the bundle id and the version have to agree wherever the app is built.
cp Resources/Info.plist "$CONTENTS/Info.plist"

# Under a different identifier when asked.
#
# The app ships as `de.rnd7.ideai`, the App Store identifier, and the two days
# it took to get back to that are worth keeping written down.
#
# macOS files the Local Network grant under the bundle identifier and cannot
# carry one from an app's old name to its new one, so the rename for the App
# Store left the permission behind. That normally costs nothing — a renamed app
# is asked about again — but the prompt is presented by UserEventAgent through
# nehelper, and on macOS 27 up to and including beta 4 (build 26A5388g) nehelper
# refused it the connection: every request defaulted to denied and no dialog
# could appear for an app that held no grant. The denial is inherited by
# everything the app launches, so a debugger or a program under test lost the
# LAN with EHOSTUNREACH — "connect: no route to host", with nothing to click.
# The only way to work was to go back to `dev.philipparndt.ideai`, which already
# held a grant from before the rename.
#
# **Fixed in 26A5406e.** Installed under `de.rnd7.ideai` on that build, macOS
# asked for local network access the first time the app wanted it, and granting
# it restored the LAN for the app and for everything it launches. The same bug
# was reported against Ghostty, Warp, iTerm2 and VS Code, so it was the system
# rather than any of them, and it is not worth carrying a workaround for a
# version of the OS nobody is on any more.
#
# This override remains for going back — to the old identifier if the grant is
# ever lost again, or to a throwaway one for a build that must not touch the
# real app's settings or its grant. An agent building a copy to drive should use
# it, and should pass PIN_UUID=0 with it: a build under the real identifier with
# an unpinned UUID is the one combination that can take the grant away from the
# installed app.
if [ -n "${BUNDLE_ID:-}" ]; then
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS/Info.plist" >/dev/null
	echo "    bundle id: $BUNDLE_ID"
fi

# Stamped with the commit it was built from, so "did my build actually get
# installed" is a question with an answer. `CFBundleVersion` is the build
# number, and the count of commits is one that only ever goes up.
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 0)
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
DIRTY=$(git diff --quiet 2>/dev/null || echo "+")
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$CONTENTS/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :AbydosCommit string $COMMIT$DIRTY" "$CONTENTS/Info.plist" >/dev/null
echo "    build $BUILD ($COMMIT$DIRTY)"

# A signature of some kind is required: macOS refuses to launch an unsigned
# bundle that was assembled by hand rather than by Xcode.
#
# A real certificate rather than ad-hoc wherever one exists, because macOS keys
# the Local Network privacy grant on the signing identity, and an ad-hoc
# signature has no team — its identity is the code directory hash, which is a
# different one after every build. The permission granted to yesterday's build
# therefore matches nothing today, and because the denial is inherited by every
# process the app spawns, a debugger or a program under test loses the LAN with
# EHOSTUNREACH — "connect: no route to host" — and no prompt to re-grant.
# `tccutil` cannot reset LocalNetwork, so the only way back is the System
# Settings pane, by hand, after each build. The Apple Development certificate
# keeps the identity stable across rebuilds and the grant stays granted.
# Before signing, because patching a binary afterwards breaks the signature.
#
# The Local Network grant is filed against the executable's UUID, which the
# linker derives from content — so a rebuild loses it, and on this macOS beta no
# new one can be granted, since the prompt cannot be presented. Everything the
# app launches inherits the denial, which is a debugger reporting "connect: no
# route to host" about a broker that is up. Pinning the UUID to one that is
# already associated keeps a build compiled a minute ago able to reach the
# network. `PIN_UUID=0` turns it off, which is what a release does: identical
# UUIDs make crash reports ambiguous about which build produced them.
#
# The second line is here rather than in a document because this is the only
# moment somebody sees the pinning happen. The UUID is also what every
# symbolicating tool uses to decide whose symbols to print, so a pinned build is
# one `sample` and `atos` will describe using another build's names — silently,
# and convincingly, since the names are all from this repository. 0447 has the
# measurement; `make profile` builds one that can be read.
PIN_UUID="${PIN_UUID:-C94373A9-FCB2-3966-B045-208B26A4CA30}"
if [ "$PIN_UUID" != "0" ]; then
	python3 Scripts/pin-uuid.py "$CONTENTS/MacOS/Abydos" "$PIN_UUID"
	echo "    a pinned build cannot be profiled — 'make profile' builds one that can"
fi

# **Liquid glass, and how to not have it.**
#
# macOS 26 decides whether an app gets the Tahoe appearance — glass capsules
# behind every toolbar item — from the SDK the binary was *linked* against, not
# from the OS it runs on. `Package.swift` pins the minimum to macOS 14, which is
# not the same thing: `vtool -show-build` reports `sdk 26.5` for anything built
# with the Xcode on this machine, and `sdk 14.0` for the copy Homebrew ships.
# That is the entire difference between the two, and the reason a local build
# suddenly grew white pills in a dark toolbar while the installed one did not.
#
# There is no supported switch to ask for the old look: AppKit carries no
# Info.plist key for it — the iOS `UIDesignRequiresCompatibility` has no macOS
# equivalent that could be found — and building against the macOS 15 SDK fails
# outright, because Xcode 26's compiler cannot use that SDK's standard library
# (`cannot find type 'SendableMetatype' in scope`). So the marker AppKit reads is
# rewritten after linking, which is what `vtool` is for.
#
# **What this trades away.** It tells the OS the binary was built against an
# older SDK, and every SDK-gated behaviour change goes with it, not only the one
# being asked for. Availability is checked at runtime, so an `if #available` for
# a macOS 26 API still works. `GLASS=1` builds without the rewrite, which is how
# to see what a user on Tahoe actually sees — and worth doing before shipping a
# toolbar, because the Homebrew build's own SDK will move eventually.
if [ "${GLASS:-0}" != "1" ]; then
	if vtool -set-build-version macos 14.0 14.0 -replace \
		-output "$CONTENTS/MacOS/Abydos.legacy" "$CONTENTS/MacOS/Abydos" >/dev/null 2>&1
	then
		mv "$CONTENTS/MacOS/Abydos.legacy" "$CONTENTS/MacOS/Abydos"
		echo "    marked as built against the macOS 14 SDK (GLASS=1 to keep the Tahoe look)"
	else
		rm -f "$CONTENTS/MacOS/Abydos.legacy"
		echo "    warning: could not rewrite the SDK marker; the toolbar will be glass" >&2
	fi
fi

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
	# By hash, not by name. `--sign "Apple Development"` is a *prefix match over
	# the certificate's name*, and a keychain can hold two certificates whose
	# names are character-for-character identical — renewing a development
	# certificate without deleting the old one is all it takes. codesign then
	# refuses the whole thing with
	#
	#     Apple Development: … : ambiguous (matches … and … in login.keychain-db)
	#
	# The hash in the first column is unique by construction, so it cannot be
	# ambiguous however many certificates share a name.
	#
	# This cost an afternoon in the worst possible shape: the signing failure was
	# a *warning*, the bundle went out carrying only the ad-hoc signature the
	# linker puts on, `make install` put it in /Applications, and the kernel
	# killed it at launch with `CODESIGNING / Invalid Page` — a crash report full
	# of dyld frames and nothing at all about a certificate.
	IDENTITY=$(security find-identity -v -p codesigning \
		| awk '/"Apple Development/ { print $2; exit }')
	if [ -z "$IDENTITY" ]; then
		IDENTITY="-"
		echo "    no Apple Development certificate: signing ad-hoc, so Local Network"
		echo "    access must be re-granted in System Settings after every build"
	fi
fi

# With the hardened runtime, which is what the release build has signed with
# all along. macOS decides whether an app may use the local network partly on
# what its signature says about it, and a development build that differs from
# the shipped one there is a build whose network failures nobody can reproduce
# in the thing they will actually run.
if SIGN_OUT=$(codesign --force --deep --options runtime --sign "$IDENTITY" "$APP" 2>&1); then
	echo "    signed with: $IDENTITY"
elif [ "$IDENTITY" = "-" ]; then
	# Ad-hoc failing is not something to carry on from: there is no simpler
	# thing left to try.
	echo "    error: ad-hoc codesign failed" >&2
	echo "$SIGN_OUT" | sed 's/^/    /' >&2
	exit 1
else
	# A real ad-hoc signature rather than whatever the linker left, and said
	# rather than warned about. An app that is not signed is an app the kernel
	# kills at launch, so "the app may not launch" was the wrong mood entirely —
	# and a warning on line 240 of a build that then prints `==> Done` is a
	# warning nobody reads.
	echo "    codesign with '$IDENTITY' failed:" >&2
	echo "$SIGN_OUT" | sed 's/^/    /' >&2
	if ! SIGN_OUT=$(codesign --force --deep --options runtime --sign - "$APP" 2>&1); then
		echo "    error: falling back to an ad-hoc signature failed too" >&2
		echo "$SIGN_OUT" | sed 's/^/    /' >&2
		exit 1
	fi
	echo "    signed ad-hoc instead: it will launch, but Local Network access" >&2
	echo "    has to be re-granted in System Settings" >&2
fi

# Asked of codesign rather than assumed, because the whole failure this guards
# against was a bundle that looked built and could not start. `--strict` is what
# notices a signature that does not cover the resources.
if ! VERIFY_OUT=$(codesign --verify --strict "$APP" 2>&1); then
	echo "    error: the signed bundle does not verify" >&2
	echo "$VERIFY_OUT" | sed 's/^/    /' >&2
	exit 1
fi

echo "==> Done: $APP"
