#!/bin/sh
set -eu

app_path="${1:-build/chicago}"
output_path="${2:-build/theme-knoll-full.png}"
page_one="/private/tmp/chicago-vulkan-theme-knoll.png"
page_two="/private/tmp/chicago-vulkan-theme-knoll-details.png"
work_dir="${TMPDIR:-/private/tmp}/chicago-theme-knoll-capture"

mkdir -p "$work_dir" "$(dirname "$output_path")"
"$app_path" --capture-theme-knoll || test -f "$page_one"
"$app_path" --capture-theme-knoll-details || test -f "$page_two"
cp "$page_one" "$work_dir/page-01.png"
cp "$page_two" "$work_dir/page-02.png"
magick "$work_dir/page-01.png" "$work_dir/page-02.png" -append "$output_path"
echo "captured full theme knoll: $output_path"
