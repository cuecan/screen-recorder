#!/bin/sh
# Run by the CueCan target's "Embed cuecan CLI" build phase.
#
# The app target depends on the `cuecan` product of Packages/CueCanKit, so Xcode builds it into
# BUILT_PRODUCTS_DIR. This copies it to CueCan.app/Contents/Helpers/cuecan and signs it with the
# app's identity and the hardened runtime. It has to be signed before Xcode signs the app, which
# happens after every build phase.
#
# It goes in Contents/Helpers, Apple's place for command-line tools in a bundle, because a
# `cuecan` in Contents/MacOS would collide with the app's own `CueCan` executable on a
# case-insensitive disk. Xcode can't add a package's executable to a Copy Files phase, which is
# why this is a script.
set -eu

src="$BUILT_PRODUCTS_DIR/cuecan"
dst="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/cuecan"

mkdir -p "$(dirname "$dst")"

if [ "${CODE_SIGNING_ALLOWED:-YES}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    timestamp="--timestamp=none"
    if [ "$CONFIGURATION" = "Release" ]; then
        timestamp="--timestamp"
    fi
    # Sign a copy in a temporary folder, then copy the signed file in. codesign (and ditto) write a
    # temporary file beside the file they write, which user script sandboxing refuses inside the app
    # bundle because it isn't a declared output. cp writes straight to the declared output.
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
    ditto "$src" "$work/cuecan"
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime "$timestamp" \
        --identifier "$PRODUCT_BUNDLE_IDENTIFIER.cuecan" "$work/cuecan"
    cp -fp "$work/cuecan" "$dst"
else
    cp -fp "$src" "$dst"
fi
