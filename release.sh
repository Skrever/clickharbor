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
artifact_name="ClickHarbor-${version}-macOS-universal"
archive="$artifact_name.zip"
disk_image="$artifact_name.dmg"
stage_dir=$(mktemp -d "$output_dir/.release.XXXXXX")
trap 'rm -rf -- "$stage_dir"' EXIT

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$stage_dir/$archive"
/usr/bin/unzip -tq "$stage_dir/$archive"

image_contents="$stage_dir/image"
mkdir "$image_contents"
/usr/bin/ditto "$app_path" "$image_contents/ClickHarbor.app"
ln -s /Applications "$image_contents/Applications"
/usr/bin/hdiutil create -quiet -volname ClickHarbor -fs HFS+ -format UDZO \
    -srcfolder "$image_contents" "$stage_dir/$disk_image"
/usr/bin/hdiutil verify -quiet "$stage_dir/$disk_image"

(
    cd -- "$stage_dir"
    for artifact in "$archive" "$disk_image"; do
        /usr/bin/shasum -a 256 "$artifact" > "$artifact.sha256"
        /usr/bin/shasum -a 256 -c "$artifact.sha256"
    done
)

for artifact in "$archive" "$disk_image"; do
    mv -f -- "$stage_dir/$artifact" "$stage_dir/$artifact.sha256" "$output_dir/"
    printf '%s\n' "$output_dir/$artifact" "$output_dir/$artifact.sha256"
done
