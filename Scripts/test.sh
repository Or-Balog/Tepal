#!/usr/bin/env bash
set -euo pipefail
repository_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repository_root"
build_root="${TEPAL_BUILD_ROOT:-$repository_root/.build}"
export CLANG_MODULE_CACHE_PATH="$build_root/clang-module-cache"
developer_dir="$(xcode-select -p)"
framework_dir="$developer_dir/Library/Developer/Frameworks"
swift_options=(--disable-sandbox --scratch-path "$build_root" --cache-path "$build_root/swiftpm-cache")
# Some Command Line Tools releases omit the Testing framework's search/rpath.
if [[ "$developer_dir" == */CommandLineTools && -d "$framework_dir/Testing.framework" ]]; then
  swift_options+=(-Xswiftc -F -Xswiftc "$framework_dir" -Xlinker -rpath -Xlinker "$framework_dir" -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/usr/lib")
fi
swift test "${swift_options[@]}" "$@"
