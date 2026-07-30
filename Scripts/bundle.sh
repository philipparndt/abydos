#!/bin/bash
#
# Wraps the SPM executable into a real .app.
#
# The bundle is what gives ideai a Dock presence, a proper unified titlebar, and
# — importantly — a `Bundle.main.resourceURL` that the grammar query bundles can
# be found under at runtime.
#
# Usage: Scripts/bundle.sh [debug|release]   (default: release)

set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/ideai.app"
CONTENTS="$APP/Contents"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_DIR/ideai" "$CONTENTS/MacOS/ideai"

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

# Bundled fonts, registered at launch so powerline prompts render without the
# user installing anything.
if [ -d Resources/Fonts ]; then
	mkdir -p "$CONTENTS/Resources/Fonts"
	cp Resources/Fonts/*.ttf "$CONTENTS/Resources/Fonts/" 2>/dev/null || true
	cp Resources/Fonts/LICENSE-* "$CONTENTS/Resources/Fonts/" 2>/dev/null || true
	echo "    bundled $(ls "$CONTENTS/Resources/Fonts"/*.ttf 2>/dev/null | wc -l | tr -d ' ') fonts"
fi

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>ideai</string>
	<key>CFBundleDisplayName</key>
	<string>ideai</string>
	<key>CFBundleIdentifier</key>
	<string>dev.philipparndt.ideai</string>
	<key>CFBundleExecutable</key>
	<string>ideai</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<!-- Dark by default; the theme is a fixed dark palette for now. -->
	<key>NSRequiresAquaSystemAppearance</key>
	<false/>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>
			<string>Folder</string>
			<key>CFBundleTypeRole</key>
			<string>Viewer</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>public.folder</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
PLIST

# Ad-hoc signature: without it macOS refuses to launch an unsigned bundle that
# was assembled by hand rather than by Xcode.
codesign --force --deep --sign - "$APP" 2>/dev/null || \
	echo "    warning: ad-hoc codesign failed; the app may not launch"

echo "==> Done: $APP"
