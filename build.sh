#!/bin/bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
output_dir="$project_dir/build"
app_path="$output_dir/ClickHarbor.app"
mkdir -p "$output_dir"

if [[ ${CLICKHARBOR_PACKAGING_LOCKED:-} != 1 ]]; then
    exec /usr/bin/lockf -k "$output_dir/.packaging.lock" \
        /usr/bin/env CLICKHARBOR_PACKAGING_LOCKED=1 /bin/bash "$project_dir/build.sh"
fi

cd -- "$project_dir"
module_cache="$project_dir/.build/ModuleCache.noindex"
mkdir -p "$module_cache"
export CLANG_MODULE_CACHE_PATH="$module_cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$module_cache"

stage_dir=$(mktemp -d "$output_dir/.clickharbor.XXXXXX")
staged_app="$stage_dir/ClickHarbor.app"
previous_app="$stage_dir/previous.app"
cleanup() {
    if [[ -d "$previous_app" && ! -e "$app_path" ]]; then
        mv -- "$previous_app" "$app_path" || return
    fi
    rm -rf -- "$stage_dir"
}
trap cleanup EXIT

mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
binary="$staged_app/Contents/MacOS/AiroxUtility"
slice_paths=()
for cpu in arm64 x86_64; do
    swift_flags=(--configuration release --triple "$cpu-apple-macosx14.0")
    xcrun swift build "${swift_flags[@]}" --product AiroxUtility
    bin_dir=$(xcrun swift build "${swift_flags[@]}" --show-bin-path)
    slice_paths+=("$bin_dir/AiroxUtility")
done
xcrun lipo -create "${slice_paths[@]}" -output "$binary"
chmod 0755 "$binary"
xcrun lipo "$binary" -verify_arch arm64 x86_64

/usr/bin/install -m 0644 Resources/Info.plist "$staged_app/Contents/Info.plist"
xcrun swift -module-cache-path "$module_cache" Resources/MakeAppIcon.swift \
    "$staged_app/Contents/Resources/AppIcon.icns"
if [[ -n ${CLICKHARBOR_SIGN_IDENTITY:-} ]]; then
    /usr/bin/codesign --force --options runtime --sign "$CLICKHARBOR_SIGN_IDENTITY" --timestamp "$staged_app"
else
    /usr/bin/codesign --force --sign - --timestamp=none "$staged_app"
fi
/usr/bin/codesign --verify --strict "$staged_app"

if [[ -e "$app_path" || -L "$app_path" ]]; then
    old_id=$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$app_path/Contents/Info.plist" 2>/dev/null || true)
    new_id=$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - Resources/Info.plist)
    if [[ -L "$app_path" || "$old_id" != "$new_id" ]]; then
        printf 'The output path already contains another item. %s\n' "$app_path" >&2
        exit 1
    fi
    mv -- "$app_path" "$previous_app"
fi

mv -- "$staged_app" "$app_path"
printf '%s\n' "$app_path"
