#!/usr/bin/env bash
#
# Packages the Flutter Linux release bundle as an AppImage.
#
#   make-appimage.sh <bundle-dir> <output-file>
#   make-appimage.sh desktop/build/linux/x64/release/bundle Rekindle.AppImage
#
# The bundle is already relocatable — linux/CMakeLists.txt sets an $ORIGIN/lib
# rpath — so it drops into usr/bin/ untouched and runs from wherever the
# AppImage happens to be mounted. GTK and friends come from the host, exactly as
# they do for the portable zip, so there is no library bundling to keep in sync.

set -euo pipefail

APPIMAGETOOL_VERSION=1.9.1
APPIMAGETOOL_SHA256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0

if [ $# -ne 2 ]; then
  echo "usage: $(basename "$0") <bundle-dir> <output-file>" >&2
  exit 2
fi

bundle=$1
output=$2
here=$(cd "$(dirname "$0")" && pwd)

[ -x "$bundle/rekindle" ] || { echo "no rekindle binary in $bundle" >&2; exit 1; }

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

appdir=$workdir/Rekindle.AppDir
mkdir -p "$appdir/usr/bin" \
         "$appdir/usr/share/applications" \
         "$appdir/usr/share/icons/hicolor/256x256/apps"

cp -a "$bundle/." "$appdir/usr/bin/"

# appimagetool requires AppRun, one .desktop and a matching icon at the AppDir
# root. It runs desktop-file-validate, which rejects CRLF, so normalise on the
# way in rather than depend on how the checkout landed.
install -m 755 "$here/AppRun" "$appdir/AppRun"
sed 's/\r$//' "$here/../rekindle.desktop" > "$appdir/rekindle.desktop"
chmod 644 "$appdir/rekindle.desktop"
install -m 644 "$here/../icon.png" "$appdir/rekindle.png"

# Desktop environments read these once the AppImage is integrated (by
# AppImageLauncher, appimaged, or by hand).
install -m 644 "$appdir/rekindle.desktop" "$appdir/usr/share/applications/rekindle.desktop"
install -m 644 "$appdir/rekindle.png" "$appdir/usr/share/icons/hicolor/256x256/apps/rekindle.png"

tool=$workdir/appimagetool
curl -fsSL --retry 3 -o "$tool" \
  "https://github.com/AppImage/appimagetool/releases/download/${APPIMAGETOOL_VERSION}/appimagetool-x86_64.AppImage"
echo "$APPIMAGETOOL_SHA256  $tool" | sha256sum -c -
chmod +x "$tool"

# CI runners have no FUSE, so appimagetool has to unpack itself in order to run.
APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 "$tool" "$appdir" "$output"
