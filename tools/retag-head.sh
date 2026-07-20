#!/usr/bin/env bash
#
# Move a release tag to the current HEAD and force-push only that tag to origin.
# Defaults to the latest local SemVer tag; an explicit tag may be supplied.
#
# Usage:
#   tools/retag-head.sh [vMAJOR.MINOR.PATCH[-prerelease]]

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [vMAJOR.MINOR.PATCH[-prerelease]]" >&2
  exit 2
fi

TAG="${1:-$(git tag --list 'v[0-9]*' --sort=-version:refname | head -n 1)}"
if [[ -z "$TAG" ]]; then
  echo "error: no local release tag found; pass a tag explicitly" >&2
  exit 1
fi
if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "error: '$TAG' is not a valid release tag" >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  git tag -d "$TAG"
else
  echo "note: no local tag $TAG (creating fresh at HEAD)"
fi

git tag "$TAG"
echo "Tagged $TAG at $(git rev-parse --short HEAD)"

git push origin "$TAG" --force
