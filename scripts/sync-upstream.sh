#!/bin/bash
# Syncs the local CleanShot patch (branch local-cleanshot) with the newest
# upstream release: fetch, rebase, build, install, relaunch.
#
# The local changes live as a commit (or commits) on local-cleanshot; this
# script never commits or stashes anything on its own.
#
# Usage: scripts/sync-upstream.sh [--build-only]
set -euo pipefail
cd "$(dirname "$0")/.."

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "error: working tree is dirty — commit the local changes first." >&2
  exit 1
fi

git fetch origin --tags --prune

TAG="$(git tag --list 'v*' --sort=-v:refname | head -1)"
echo "Newest upstream release: $TAG"

if git merge-base --is-ancestor "$TAG" HEAD; then
  echo "Already on or past $TAG; nothing to rebase."
else
  echo "Rebasing local-cleanshot onto $TAG…"
  if ! git rebase "$TAG"; then
    cat >&2 <<'MSG'
Rebase stopped with conflicts. Resolve them, then run:
  git add -A && git rebase --continue
  scripts/sync-upstream.sh
The usual conflict spots: AppDelegate.swift (menu), GrabArea.swift and
ClipboardWatcher.swift (CleanShot hooks), the two Localizable.strings.
MSG
    exit 1
  fi
fi

bash scripts/build-app.sh

if [ "${1:-}" = "--build-only" ]; then
  echo "Built only. To install: quit Tendedero, then:"
  echo "  ditto build/Tendedero.app /Applications/Tendedero.app"
  exit 0
fi

pkill -TERM -x Tendedero 2>/dev/null || true
sleep 2
ditto build/Tendedero.app /Applications/Tendedero.app
open -a Tendedero
VERSION="$(defaults read /Applications/Tendedero.app/Contents/Info CFBundleShortVersionString)"
echo "Installed Tendedero $VERSION and relaunched. Smoke test: a capture hangs,"
echo "hover shows the buttons, Copy closes the photo."
