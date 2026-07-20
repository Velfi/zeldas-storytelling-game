#!/usr/bin/env bash
# Validate, tag, and start a GitHub release build.
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "usage: $0 MAJOR.MINOR.PATCH[-prerelease]" >&2
  exit 2
fi

VERSION="$1"
TAG="v$VERSION"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[[ "$(git branch --show-current)" == "main" ]] || { echo "error: releases must run from main" >&2; exit 1; }
git diff --quiet && git diff --cached --quiet || { echo "error: working tree is not clean" >&2; git status --short >&2; exit 1; }
git remote get-url origin >/dev/null 2>&1 || { echo "error: origin is not configured" >&2; exit 1; }
git fetch origin main --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "error: local main and origin/main differ" >&2; exit 1; }
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "error: $TAG already exists" >&2; exit 1; }
! git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1 || { echo "error: $TAG already exists on origin" >&2; exit 1; }

git tag -a "$TAG" -m "Release $TAG"
echo "Created $TAG at $(git rev-parse --short HEAD)."
read -r -p "Push tag and start the release workflow? [y/N] " answer
case "$answer" in
  y|Y|yes|YES|Yes)
    git push origin "$TAG"
    echo "Release started: https://github.com/Velfi/zeldas-storytelling-game/actions/workflows/release.yml"
    ;;
  *)
    echo "Not pushed. Run 'git push origin $TAG' later, or 'git tag -d $TAG' to cancel."
    ;;
esac
