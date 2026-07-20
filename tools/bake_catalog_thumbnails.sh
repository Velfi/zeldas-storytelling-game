#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
binary="$root_dir/build/chicago"
output_dir="$root_dir/assets/ui/catalog"

if [ ! -x "$binary" ]; then
    make -C "$root_dir" build
fi

mkdir -p "$output_dir"

if [ "$#" -gt 0 ]; then
    ids="$*"
else
    ids=$(awk '
        /^\[\[objects\]\]/ { in_object=1; next }
        /^\[\[/ { in_object=0 }
        in_object && /^id[[:space:]]*=/ {
            line=$0
            sub(/^[^=]*=[[:space:]]*"/, "", line)
            sub(/".*/, "", line)
            print line
        }
    ' "$root_dir/assets/catalog/editor_catalog.toml")
fi
for id in $ids; do
    "$binary" --capture-catalog-thumbnail "$id"
    source_png="/private/tmp/chicago-catalog-$id.png"
    dimensions=$(magick identify -format '%w %h' "$source_png")
    set -- $dimensions
    width=$1
    height=$2
    if [ "$width" -lt "$height" ]; then square=$width; else square=$height; fi
    magick "$source_png" -gravity center -crop "${square}x${square}+0+0" +repage -resize 256x256 "$output_dir/$id.png"
    echo "baked $output_dir/$id.png"
done
