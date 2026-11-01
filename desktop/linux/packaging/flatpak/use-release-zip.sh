#!/usr/bin/env bash
# Points the Flatpak manifest at a client zip downloaded from URL, in place of
# the release it is pinned to, so a release can package the zip it has just
# published. The manifest itself is bumped to the new release afterwards.
#
# Usage: use-release-zip.sh URL
# Edits the manifest in place; run it in a throwaway checkout (CI).
set -euo pipefail

url=${1:?usage: use-release-zip.sh URL}
dir=$(cd "$(dirname "$0")" && pwd)
manifest="$dir/io.github.Jombolio.Rekindle.yml"
zip=RekindleClient-linux-x64.zip

curl -fsSL --retry 5 --retry-delay 10 -o "$dir/$zip" "$url"

# The archive source becomes a local path; its sha256 pinned the old zip.
sed -i -E \
  -e "s#^([[:space:]]*)url: .*/${zip}\$#\1path: ${zip}#" \
  -e '/^[[:space:]]*sha256: /d' \
  "$manifest"

if ! grep -qE "^[[:space:]]*path: ${zip}\$" "$manifest" \
   || grep -qE "^[[:space:]]*url: .*/${zip}\$" "$manifest"; then
  echo "::error::Couldn't point $manifest at the downloaded $zip."
  exit 1
fi
echo "Manifest now builds from $url"
