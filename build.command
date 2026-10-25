#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
WORK="$(mktemp -d /private/tmp/notes-build.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/Notes.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/assets"
xcrun swiftc -module-cache-path /private/tmp/notes-swift-cache "$ROOT/source/MakeIcon.swift" -o "$WORK/make-icon"
"$WORK/make-icon" "$ROOT/assets/provided-icon.png" "$ROOT/assets/AppIcon.png"
mkdir "$WORK/AppIcon.iconset"
for size in 16 32 128 256 512; do
 sips -z "$size" "$size" "$ROOT/assets/AppIcon.png" --out "$WORK/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
 double=$((size*2));sips -z "$double" "$double" "$ROOT/assets/AppIcon.png" --out "$WORK/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/AppIcon.iconset" -o "$ROOT/assets/AppIcon.icns"
xcrun swiftc -parse-as-library -O -target arm64-apple-macos14.0 -module-cache-path /private/tmp/notes-swift-cache -framework AppKit -framework WebKit -framework PDFKit "$ROOT/source/NotesApp.swift" "$ROOT/source/NoteStore.swift" "$ROOT/source/Export.swift" "$ROOT/source/PDFComposer.swift" "$ROOT/source/StoreTests.swift" "$ROOT/source/EditorQA.swift" "$ROOT/source/ExpiryAgent.swift" -o "$APP/Contents/MacOS/CompagnonsNotes"
cp "$ROOT/source/index.html" "$ROOT/source/editor.css" "$ROOT/source/editor.js" "$ROOT/source/qa.js" "$ROOT/assets/AppIcon.png" "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/"
mv "$APP/Contents/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon-v2.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.compagnons.notes</string>
<key>CFBundleName</key><string>Notes</string>
<key>CFBundleDisplayName</key><string>Notes</string>
<key>CFBundleExecutable</key><string>CompagnonsNotes</string>
<key>CFBundleIconFile</key><string>AppIcon-v2.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2.0</string>
<key>CFBundleVersion</key><string>6</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
<key>NSHumanReadableCopyright</key><string>Notes — Compagnons. Application personnelle indépendante.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
if [[ -d "$ROOT/Notes.app" ]]; then rm -rf "$ROOT/Notes.app"; fi
ditto --noextattr --norsrc "$APP" "$ROOT/Notes.app"
print "Construit : $ROOT/Notes.app"
