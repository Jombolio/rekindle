#!/usr/bin/env bash
# Creates the Gitea release for a version tag, or reuses it if it exists, and
# writes its id and tag to $GITHUB_OUTPUT for the jobs that attach files.
#
# - A tag with a pre-release suffix (v1.5.0-beta.1) becomes a pre-release.
# - The tag must match <Version> in server/Directory.Build.props at the tagged
#   commit, so a release can't go out with the wrong version inside.
# - Notes come from release-notes/<tag>.md if present, else the commits since
#   the previous version tag.
#
# Environment: TAG, GITEA_TOKEN, GITEA_SERVER_URL, GITEA_REPOSITORY
# Run from a checkout with tags fetched. Needs git, curl and jq.
set -euo pipefail

: "${TAG:?TAG is not set}"
: "${GITEA_TOKEN:?GITEA_TOKEN is not set}"
: "${GITEA_SERVER_URL:?GITEA_SERVER_URL is not set}"
: "${GITEA_REPOSITORY:?GITEA_REPOSITORY is not set}"

semver='^v([0-9]+)\.([0-9]+)\.([0-9]+)(-[0-9A-Za-z.-]+)?$'
if ! [[ "$TAG" =~ $semver ]]; then
  echo "::error::'$TAG' is not a version tag like v1.5.0 or v1.5.0-beta.1."
  exit 1
fi
version=${TAG#v}
prerelease=false
[[ "$version" == *-* ]] && prerelease=true

if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "::error::Tag $TAG does not exist in this repository."
  exit 1
fi

built=$(git show "$TAG:server/Directory.Build.props" | sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' | head -1)
if [ "$built" != "$version" ]; then
  echo "::error::Tag $TAG doesn't match server/Directory.Build.props at that commit ($built). Bump the version before tagging."
  exit 1
fi

api="${GITEA_SERVER_URL%/}/api/v1/repos/${GITEA_REPOSITORY}/releases"
auth=(-H "Authorization: token ${GITEA_TOKEN}")

# Reuse a release that already exists for the tag: a re-run, or one made by
# hand in the web UI. Its notes and flags are left as they are.
code=$(curl -sS -o existing.json -w '%{http_code}' "${auth[@]}" "$api/tags/$TAG")
if [ "$code" = 200 ]; then
  id=$(jq -r .id existing.json)
  echo "Release for $TAG already exists (id $id); attaching files to it."
elif [ "$code" = 404 ]; then
  notes_file="release-notes/$TAG.md"
  if [ -f "$notes_file" ]; then
    body=$(cat "$notes_file")
    echo "Notes from $notes_file"
  else
    # The newest version tag before this one, by version order.
    previous=$(git tag --list 'v[0-9]*' --sort=-v:refname | grep -vxF "$TAG" \
      | while read -r t; do
          if [ "$(printf '%s\n%s\n' "$t" "$TAG" | sort -V | tail -1)" = "$TAG" ]; then echo "$t"; break; fi
        done)
    range=${previous:+$previous..}$TAG
    body="Changes${previous:+ since $previous}:"$'\n\n'$(git log --no-merges --format='- %s' "$range")
    echo "No $notes_file; notes are the commits in $range."
  fi

  jq -n --arg tag "$TAG" --arg name "Rekindle $TAG" --arg body "$body" --argjson pre "$prerelease" \
    '{tag_name: $tag, name: $name, body: $body, draft: false, prerelease: $pre}' \
    | curl -fsS -X POST "${auth[@]}" -H 'Content-Type: application/json' --data @- "$api" > created.json
  id=$(jq -r .id created.json)
  kind=release
  [ "$prerelease" = true ] && kind=pre-release
  echo "Created $kind Rekindle $TAG (id $id)."
else
  echo "::error::Looking up the release for $TAG returned HTTP $code."
  cat existing.json >&2 || true
  exit 1
fi
rm -f existing.json created.json

[[ "$id" =~ ^[0-9]+$ ]] || { echo "::error::Gitea returned no release id."; exit 1; }
echo "id=$id" >> "${GITHUB_OUTPUT:-/dev/stdout}"
echo "tag=$TAG" >> "${GITHUB_OUTPUT:-/dev/stdout}"
