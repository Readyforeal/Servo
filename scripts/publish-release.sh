#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
VERSION=$(<VERSION)
REPOSITORY=$(<UPDATE_REPOSITORY)
DMG="dist/Servo-$VERSION-arm64.dmg"
[[ -f "$DMG" ]] || { echo "Build a signed release first with scripts/release.sh" >&2; exit 1; }
[[ -z $(git status --porcelain) ]] || { echo "Commit changes before publishing" >&2; exit 1; }
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
git fetch origin main
[[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || { echo "Push the release commit to origin/main first" >&2; exit 1; }
# Publish a reviewable draft; mark it published on GitHub after testing on a second Mac.
gh release create "v$VERSION" "$DMG" "$DMG.sha256" --repo "$REPOSITORY" \
  --target "$(git rev-parse HEAD)" --title "Servo $VERSION" --generate-notes --draft
echo "Draft release created. Test the DMG on another Mac, then publish it on GitHub."
