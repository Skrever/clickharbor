#!/bin/bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
output_dir="$project_dir/build"
mkdir -p "$output_dir"

if [[ ${CLICKHARBOR_PACKAGING_LOCKED:-} != 1 ]]; then
    exec /usr/bin/lockf -k "$output_dir/.packaging.lock" \
        /usr/bin/env CLICKHARBOR_PACKAGING_LOCKED=1 /bin/bash "$project_dir/release.sh"
fi

"$project_dir/build.sh"
app_path="$output_dir/ClickHarbor.app"
version=$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$app_path/Contents/Info.plist")
archive="ClickHarbor-${version}-macOS-universal.zip"
stage_dir=$(mktemp -d "$output_dir/.release.XXXXXX")
trap 'rm -rf -- "$stage_dir"' EXIT

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$stage_dir/$archive"
/usr/bin/unzip -tq "$stage_dir/$archive"
(
    cd -- "$stage_dir"
    /usr/bin/shasum -a 256 "$archive" > "$archive.sha256"
    /usr/bin/shasum -a 256 -c "$archive.sha256"
)
mv -f -- "$stage_dir/$archive" "$stage_dir/$archive.sha256" "$output_dir/"

printf '%s\n' "$output_dir/$archive" "$output_dir/$archive.sha256"
