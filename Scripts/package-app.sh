#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 [debug|release]" >&2
  echo "Tepal has one app profile, with optional double-knock support." >&2
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
codesign --force --sign - --entitlements "$entitlements" "$staged_app"
codesign --verify --deep --strict "$staged_app"

rm -rf "$destination"
mv "$staged_app" "$destination"
printf '%s\n' "$destination"
