# Releases and updates

Servo currently requires **Apple silicon and macOS 14 or newer**. It is not compatible with older macOS versions or Intel Macs. Normal local builds are ad hoc signed. A development DMG does not provide Developer ID trust or notarization.

## One-time setup

1. Enroll in the Apple Developer Program, sign into Xcode, and install a **Developer ID Application** certificate with its private key in your login Keychain. `security find-identity -v -p codesigning` must list it. Never commit exported certificates or credentials.
2. Configure a notarization Keychain profile interactively with `xcrun notarytool store-credentials ServoNotary`. Use your Apple account, team ID, and an app-specific password (or Apple's supported API-key authentication).
3. Set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if the active developer directory still points to CommandLineTools.
4. `UPDATE_REPOSITORY` holds the GitHub owner/repository. Authenticate the release machine with `gh auth login`.

## Build a distribution DMG

Update `VERSION` (three numeric components) and increment `BUILD_NUMBER`. Commit the release changes.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export NOTARY_PROFILE=ServoNotary
./scripts/release.sh
```

The script bundles the native layered icon, signs the app with hardened runtime and a secure timestamp, notarizes and staples the app, creates a drag-to-Applications DMG, signs/notarizes/staples that DMG, and verifies Gatekeeper acceptance. The build fails if any step fails. Credentials are read from Keychain, never embedded in Servo.

For a clearly marked local test installer only: `./scripts/release.sh --development`.

## Publish

Push the release commit to `origin/main`, then run `./scripts/publish-release.sh`. It refuses development or unnotarized DMGs and creates a **draft** GitHub release. Test installation and launch on another Mac, including terminal, browser, file access and Servo matching. Publish the draft after verification.

## Check for Updates

Servo → Check for Updates queries GitHub's latest published, non-prerelease release. It compares semantic versions and offers the matching `Servo-VERSION-arm64.dmg`. It opens the download in the user's browser; quit Servo and drag the replacement into Applications. This is a manual installation flow, not a silent self-updater. Workspace data remains in Application Support and credentials in Keychain. Source commits alone are not updates.

This repository is public. Update checks require no GitHub login or embedded token. Development prereleases are excluded from normal update checks. The installer is opened in the user's browser; it does not silently replace the running app. Quit Servo before installing, which stops its running servers, then relaunch and restart the sites you need.

Apple references: https://developer.apple.com/developer-id/ and https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
