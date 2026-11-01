#!/usr/bin/env bash
# Attaches files to a Gitea release, replacing any existing asset with the same
# name (the equivalent of `gh release upload --clobber`, which Gitea lacks).
#
# Usage: upload-release-asset.sh FILE [FILE...]
# Environment:
#   GITEA_TOKEN       token with write access to the repository's releases
#   GITEA_SERVER_URL  e.g. https://git.example.com
#   GITEA_REPOSITORY  owner/repo
#   RELEASE_ID        numeric id of the release
# Needs curl and jq.
set -euo pipefail

: "${GITEA_TOKEN:?GITEA_TOKEN is not set}"
: "${GITEA_SERVER_URL:?GITEA_SERVER_URL is not set}"
: "${GITEA_REPOSITORY:?GITEA_REPOSITORY is not set}"
: "${RELEASE_ID:?RELEASE_ID is not set}"

api="${GITEA_SERVER_URL%/}/api/v1/repos/${GITEA_REPOSITORY}/releases/${RELEASE_ID}/assets"
auth=(-H "Authorization: token ${GITEA_TOKEN}")

for file in "$@"; do
  [ -f "$file" ] || { echo "No such file: $file" >&2; exit 1; }
  name=$(basename "$file")

  # A re-run of the job must replace what the earlier run uploaded.
  curl -fsS "${auth[@]}" "$api" \
    | jq -r --arg n "$name" '.[] | select(.name == $n) | .id' \
    | while read -r id; do
        curl -fsS -X DELETE "${auth[@]}" "$api/$id" >/dev/null
        echo "Replaced existing $name"
      done

  curl -fsS -X POST "${auth[@]}" \
    -F "attachment=@${file}" \
    "$api?name=$(jq -rn --arg n "$name" '$n | @uri')" >/dev/null
  echo "Uploaded $name"
done
