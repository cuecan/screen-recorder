#!/bin/sh
# Builds the DMG people download: a Release archive signed with the Developer ID certificate and the
# hardened runtime, checked, packed into a DMG, notarized and stapled (docs/decisions.md, 25).
#
#   scripts/release.sh                 build, sign, check, and make the DMG; notarize if the login exists
#   scripts/release.sh --skip-notarize stop before sending anything to Apple
#
# It needs three things only the maintainer has:
#   - the "Developer ID Application" certificate with its private key in a keychain (IDENTITY);
#   - a notary login: either one saved with `xcrun notarytool store-credentials` (NOTARY_PROFILE), or an
#     App Store Connect API key given as NOTARY_KEY (the .p8 file's path), NOTARY_KEY_ID and NOTARY_ISSUER;
#   - Sparkle's update signing key: either in the login keychain, made once with
#     `generate_keys --account CueCan`, or given in the SPARKLE_PRIVATE_KEY environment variable.
#     Its public half is SUPublicEDKey in Config/CueCan-Info.plist. Without the private key no installed
#     copy accepts an update, so keep a backup (`generate_keys --account CueCan -x <file>`; `-f <file>` restores it).
# Releases are made by .github/workflows/release.yml, which imports the certificate, passes the notary key
# and the update key from the repository's secrets, and runs this same script. It runs on a Mac the same way.
#
# Everything is written to build/release, which git ignores (OUT changes where), except the Swift packages
# the archive downloads, which are kept in build/SourcePackages between runs. Besides the DMG it writes
# appcast.xml, the feed Check for Updates… reads, and the DMG's SHA-256. Nothing here uploads them: the
# workflow attaches them to a GitHub release, and https://cuecan.com/mac/appcast.xml sends the app to the
# latest release's feed. DOWNLOAD_URL_PREFIX is where the DMG will be downloaded from.
#
# The build number is the number of commits, so it goes up with every release: Sparkle compares it
# (CFBundleVersion) to decide what's newer. BUILD overrides it.
set -eu

IDENTITY="${IDENTITY:-Developer ID Application: Jelled Media, LLC (YQ8JJV3BCS)}"
TEAM="${TEAM:-YQ8JJV3BCS}"
NOTARY_PROFILE="${NOTARY_PROFILE:-CueCan-notary}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-CueCan}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://cuecan.com/mac/}"
SKIP_NOTARIZE=0
[ "${1:-}" = "--skip-notarize" ] && SKIP_NOTARIZE=1

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${OUT:-$root/build/release}"
BUILD="${BUILD:-$(git -C "$root" rev-list --count HEAD)}"
# The day the build is made, in UTC. The beta stops starting recordings 90 days after it
# (docs/decisions.md, 98), so a release has to follow within that time.
BUILT_ON="${BUILT_ON:-$(date -u +%Y-%m-%d)}"
archive="$out/CueCan.xcarchive"
# Beside the output folder, not inside it: that folder is deleted on every run, and the packages would be
# downloaded again each time.
source_packages="${SOURCE_PACKAGES:-$root/build/SourcePackages}"
app="$archive/Products/Applications/CueCan.app"
helper="$app/Contents/Helpers/cuecan"

say() { printf '\n== %s\n' "$1"; }

rm -rf "$out"
mkdir -p "$out"

say "Archiving the Release build"
# ARCHS is given here as well as in the project, because the project's setting doesn't reach the packages:
# without it they are also built for Intel, which CueCan doesn't support and TranscribeKit can't compile for.
# Manual signing with the Developer ID identity: automatic signing would pick the development certificate.
# The timestamp is Apple's secure one, which notarization requires.
xcodebuild -project "$root/CueCan.xcodeproj" -scheme CueCan -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$archive" \
    -clonedSourcePackagesDirPath "$source_packages" archive \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" \
    ARCHS=arm64 \
    CURRENT_PROJECT_VERSION="$BUILD" \
    CUECAN_BUILT_ON="$BUILT_ON" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" > "$out/archive.log" 2>&1 || {
        tail -40 "$out/archive.log"
        echo "The archive failed. The whole log is $out/archive.log" >&2
        exit 1
    }

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
dmg="$out/CueCan-$version.dmg"

say "Signing Sparkle's helpers"
# Xcode signs Sparkle.framework but not the tools inside it, which arrive signed by Sparkle's own build.
# The notary service wants each with the Developer ID, the hardened runtime and a timestamp, so they're
# signed inside out, as Sparkle's documentation gives it, and then the app again, since its seal covers them.
sparkle="$app/Contents/Frameworks/Sparkle.framework"
sparkle_parts="$sparkle/Versions/B/XPCServices/Installer.xpc
$sparkle/Versions/B/XPCServices/Downloader.xpc
$sparkle/Versions/B/Autoupdate
$sparkle/Versions/B/Updater.app"
echo "$sparkle_parts" | while IFS= read -r part; do
    [ -e "$part" ] || { echo "Sparkle has no $part: its layout changed, so check how it's signed." >&2; exit 1; }
    # The downloader keeps its own entitlements.
    codesign --force --sign "$IDENTITY" --options runtime --timestamp --preserve-metadata=entitlements "$part"
done
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$sparkle"
codesign -d --entitlements "$out/app.entitlements" --xml "$app" 2>/dev/null
codesign --force --sign "$IDENTITY" --options runtime --timestamp --entitlements "$out/app.entitlements" "$app"

say "Checking the signatures of CueCan $version ($build)"
codesign --verify --deep --strict --verbose=2 "$app"
# The app, the helper it runs and Sparkle's tools must all carry the Developer ID, the hardened runtime and
# a secure timestamp, or the notary service refuses the upload.
echo "$sparkle_parts" > "$out/signed-parts"
{ echo "$app"; echo "$helper"; cat "$out/signed-parts"; } | while IFS= read -r item; do
    details="$(codesign -dvv "$item" 2>&1)"
    echo "$details" | grep -q "Authority=Developer ID Application" || { echo "$item isn't signed with the Developer ID." >&2; exit 1; }
    echo "$details" | grep -q "flags=.*runtime" || { echo "$item doesn't have the hardened runtime." >&2; exit 1; }
    echo "$details" | grep -q "^Timestamp=" || { echo "$item has no secure timestamp." >&2; exit 1; }
    echo "ok: $(basename "$item")"
done
# A debug entitlement would also be refused.
if codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q "get-task-allow"; then
    echo "The app has the get-task-allow entitlement, which notarization refuses." >&2
    exit 1
fi

say "Making the DMG"
staging="$out/dmg"
mkdir -p "$staging"
ditto "$app" "$staging/CueCan.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "CueCan" -srcfolder "$staging" -format UDZO -ov "$dmg" > /dev/null
rm -rf "$staging"
codesign --sign "$IDENTITY" --timestamp "$dmg"

if [ "$SKIP_NOTARIZE" = 1 ]; then
    say "Stopped before notarizing"
    echo "$dmg is signed but not notarized: Gatekeeper will refuse it on another Mac."
    exit 0
fi

# The notary login: an API key when one is given, as a CI run does, or else the saved keychain profile.
notary() {
    command="$1"; shift
    if [ -n "${NOTARY_KEY:-}" ]; then
        xcrun notarytool "$command" "$@" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER"
    else
        xcrun notarytool "$command" "$@" --keychain-profile "$NOTARY_PROFILE"
    fi
}

if ! notary history > /dev/null 2>&1; then
    say "No notary login"
    echo "Save one with: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <your Apple ID> --team-id $TEAM"
    echo "Or set NOTARY_KEY, NOTARY_KEY_ID and NOTARY_ISSUER to an App Store Connect API key."
    echo "$dmg is signed but not notarized: Gatekeeper will refuse it on another Mac."
    exit 2
fi

say "Notarizing (this waits for Apple)"
notary submit "$dmg" --wait | tee "$out/notary.log"
grep -q "status: Accepted" "$out/notary.log" || {
    id="$(awk '/^ *id:/ { print $2; exit }' "$out/notary.log")"
    echo "Apple didn't accept it. Its reasons:" >&2
    notary log "$id" >&2 || true
    exit 1
}

say "Stapling and checking as Gatekeeper will"
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

say "Writing the update feed"
# Signs the DMG with the update key and writes appcast.xml beside it. The key comes from
# SPARKLE_PRIVATE_KEY when that's set, passed on standard input so it never appears in a command line,
# or else from the keychain.
feed="$out/feed"
mkdir -p "$feed"
cp "$dmg" "$feed/"
# Use the artifacts this Xcode archive resolved. A clean release machine need not have run `swift test`
# in the package, so its separate .build/artifacts directory may not exist.
generate_appcast="$source_packages/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$generate_appcast" --ed-key-file - \
        --download-url-prefix "$DOWNLOAD_URL_PREFIX" -o "$out/appcast.xml" "$feed"
else
    "$generate_appcast" --account "$SPARKLE_ACCOUNT" \
        --download-url-prefix "$DOWNLOAD_URL_PREFIX" -o "$out/appcast.xml" "$feed"
fi
rm -rf "$feed"

# So anyone can check that a download is the file this run made.
(cd "$out" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")

say "Done"
echo "$dmg"
echo "$out/appcast.xml"
echo "$dmg.sha256"
