#!/bin/bash
# Build SimpleWriting.app — a self-contained macOS writing editor.
set -e
cd "$(dirname "$0")"

APP="SimpleWriting.app"
LAUNCH_AFTER_BUILD="${LAUNCH_AFTER_BUILD:-0}"

echo "🔨 Building SimpleWriting…"
swift build -c release --product SimpleWriting

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -f Info.plist "$APP/Contents/Info.plist"
cp -f ".build/release/SimpleWriting" "$APP/Contents/MacOS/SimpleWriting"
[ -f AppIcon.icns ] && cp -f AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Bundle the offline ProseMirror editor (HTML/JS/CSS).
rm -rf "$APP/Contents/Resources/editor"
cp -R Resources/editor "$APP/Contents/Resources/editor"

# Bundle the offline Math Playground (MathLive + Compute Engine).
rm -rf "$APP/Contents/Resources/math"
cp -R Resources/math "$APP/Contents/Resources/math"

# Ad-hoc sign so Gatekeeper allows a right-click → Open on the build machine.
codesign --force --deep -s - "$APP"
xattr -cr "$APP"
echo "✅ Built $APP"

if [ "$LAUNCH_AFTER_BUILD" = "1" ]; then
    open "$APP"
fi
