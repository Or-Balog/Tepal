#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 [debug|release]" >&2
  echo "Tepal has one app profile, with optional double-knock support." >&2
  echo >&2
  echo "Signing is ad-hoc unless TEPAL_SIGNING_IDENTITY names a Developer ID." >&2
  echo "Setting TEPAL_NOTARY_PROFILE additionally notarizes and staples the app:" >&2
  echo "  TEPAL_SIGNING_IDENTITY='Developer ID Application: Name (TEAMID)' \\" >&2
  echo "  TEPAL_NOTARY_PROFILE=tepal-notary $0 release" >&2
  exit 64
fi

configuration="$1"
case "$configuration" in
  debug|release) ;;
  *) echo "Configuration must be debug or release." >&2; exit 64 ;;
esac

repository_root="$(cd "$(dirname "$0")/.." && pwd -P)"
dist_root="$repository_root/dist"
destination="$dist_root/Tepal.app"
entitlements="$repository_root/Config/Tepal.entitlements"
# Ad-hoc by default so the repository builds without an Apple Developer account.
signing_identity="${TEPAL_SIGNING_IDENTITY:--}"
notary_profile="${TEPAL_NOTARY_PROFILE:-}"

if [[ -n "$notary_profile" && "$signing_identity" == "-" ]]; then
  echo "Notarization requires a Developer ID; set TEPAL_SIGNING_IDENTITY too." >&2
  exit 64
fi

cd "$repository_root"
build_root="${TEPAL_BUILD_ROOT:-$repository_root/.build}"
export CLANG_MODULE_CACHE_PATH="$build_root/clang-module-cache"
swift build -c "$configuration" --disable-sandbox --scratch-path "$build_root" --cache-path "$build_root/swiftpm-cache"
bin_path="$(swift build -c "$configuration" --show-bin-path --disable-sandbox --scratch-path "$build_root" --cache-path "$build_root/swiftpm-cache")"
executable="$bin_path/Tepal"
if [[ ! -x "$executable" ]]; then
  echo "Built executable not found: $executable" >&2
  exit 1
fi

# Validate a staged bundle before replacing the previous successful build.
mkdir -p "$dist_root"
staging_root="$(mktemp -d "$dist_root/.tepal-package.XXXXXX")"
trap 'rm -rf "$staging_root"' EXIT
staged_app="$staging_root/Tepal.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$executable" "$staged_app/Contents/MacOS/Tepal"
cp "Config/Tepal.icns" "$staged_app/Contents/Resources/Tepal.icns"
# Copy only current resources; old package bundles may remain in SwiftPM's cache.
for resource_name in Tepal_TepalApp.bundle Tepal_TepalMac.bundle; do
  cp -R "$bin_path/$resource_name" "$staged_app/Contents/Resources/"
done
cp "Config/Tepal-Info.plist" "$staged_app/Contents/Info.plist"
# The Hardened Runtime is required for notarization, and is applied to ad-hoc
# builds too so that a local build exercises the same runtime restrictions.
codesign_flags=(--force --options runtime)
# A trusted timestamp needs a real signing identity; ad-hoc signatures cannot carry one.
if [[ "$signing_identity" != "-" ]]; then
  codesign_flags+=(--timestamp)
fi
codesign "${codesign_flags[@]}" --sign "$signing_identity" --entitlements "$entitlements" "$staged_app"
codesign --verify --deep --strict "$staged_app"

if [[ -n "$notary_profile" ]]; then
  # notarytool takes an archive, not a bundle; ditto preserves the bundle layout.
  archive="$staging_root/Tepal.zip"
  ditto -c -k --keepParent "$staged_app" "$archive"
  xcrun notarytool submit "$archive" --keychain-profile "$notary_profile" --wait
  # Staple the returned ticket so the app validates without a network round trip.
  xcrun stapler staple "$staged_app"
  xcrun stapler validate "$staged_app"
  spctl --assess --verbose=4 --type execute "$staged_app"
fi

rm -rf "$destination"
mv "$staged_app" "$destination"
printf '%s\n' "$destination"

if [[ -n "$notary_profile" ]]; then
  # The archive submitted for notarization predates its own ticket. Build the
  # distributable archive from the stapled bundle instead, so a download
  # validates without contacting Apple.
  version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$repository_root/Config/Tepal-Info.plist")"
  release_archive="$dist_root/Tepal-$version.zip"
  rm -f "$release_archive"
  ditto -c -k --keepParent "$destination" "$release_archive"
  printf '%s\n' "$release_archive"
fi
