#!/bin/bash
# Build the distributable disk image.
#
# A .dmg rather than a .zip because a release asset has to be a single file and
# a .app is a directory: there is no way to attach the bundle itself. The image
# opens on a window holding the app beside a shortcut to Applications, so
# installing is one drag with no visible unarchiving step.
#
# Both forms preserve the bundle correctly. The zip must be made with `ditto`,
# never `zip`, or the executable bit, the symlinks inside Contents and the code
# signature do not survive the round trip. This script makes both, and verifies
# each by opening it again rather than trusting that it worked.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/dist/Corrector.app"
OUT="${1:-$ROOT/dist}"

VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' \
    Sources/CorrectorAppCore/Release.swift)"
STAGE="$(sed -n 's/.*static let stage = "\(.*\)".*/\1/p' \
    Sources/CorrectorAppCore/Release.swift)"
[ -n "$VERSION" ] || { echo "cannot read the version from Release.swift" >&2; exit 1; }
NAME="Corrector-$VERSION${STAGE:+-$STAGE}"

[ -d "$APP" ] || { echo "no $APP — run Tools/make-app.sh first" >&2; exit 1; }

mkdir -p "$OUT"
rm -f "$OUT/$NAME.dmg" "$OUT/$NAME.zip"

echo "==> Staging"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -R "$APP" "$WORK/"
ln -s /Applications "$WORK/Applications"

echo "==> Disk image"
hdiutil create -volname "Corrector" -srcfolder "$WORK" \
    -ov -format UDZO -quiet "$OUT/$NAME.dmg"

echo "==> Zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$NAME.zip"

echo "==> Verifying both by opening them again"
MOUNT="$(hdiutil attach "$OUT/$NAME.dmg" -nobrowse -readonly | grep -o '/Volumes/.*')"
codesign --verify --strict "$MOUNT/Corrector.app"
DMG_ARCHS="$(lipo -archs "$MOUNT/Corrector.app/Contents/MacOS/Corrector")"
hdiutil detach "$MOUNT" -quiet

CHECK="$(mktemp -d)"
ditto -x -k "$OUT/$NAME.zip" "$CHECK"
codesign --verify --strict "$CHECK/Corrector.app"
ZIP_ARCHS="$(lipo -archs "$CHECK/Corrector.app/Contents/MacOS/Corrector")"
rm -rf "$CHECK"

[ "$DMG_ARCHS" = "$ZIP_ARCHS" ] || {
    echo "the two artefacts disagree: dmg=$DMG_ARCHS zip=$ZIP_ARCHS" >&2; exit 1; }

echo
echo "    $OUT/$NAME.dmg   $(du -h "$OUT/$NAME.dmg" | cut -f1)"
echo "    $OUT/$NAME.zip   $(du -h "$OUT/$NAME.zip" | cut -f1)"
echo "    signature OK in both, architectures: $DMG_ARCHS"
echo
echo "SHA-256:"
shasum -a 256 "$OUT/$NAME.dmg" "$OUT/$NAME.zip"
