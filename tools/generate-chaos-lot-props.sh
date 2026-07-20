#!/usr/bin/env bash
set -euo pipefail

lot_path="assets/levels/chaos_lot.toml"
generated_start="# BEGIN GENERATED CHAOS PROPS"
generated_end="# END GENERATED CHAOS PROPS"
work_dir="$(mktemp -d /private/tmp/chicago-chaos-props.XXXXXX)"
clean_path="$work_dir/clean.toml"
before_path="$work_dir/before.toml"
after_path="$work_dir/after.toml"
generated_path="$work_dir/generated.toml"

# Remove an earlier generated block, leaving the hand-authored fixture intact.
awk -v start="$generated_start" -v end="$generated_end" '
  $0 == start { skipping = 1; next }
  $0 == end { skipping = 0; next }
  !skipping { print }
' "$lot_path" > "$clean_path"

awk 'BEGIN { lights = 0 } /^\[\[lights\]\]$/ { lights = 1 } !lights { print }' "$clean_path" > "$before_path"
awk 'BEGIN { lights = 0 } /^\[\[lights\]\]$/ { lights = 1 } lights { print }' "$clean_path" > "$after_path"
# Normalize the insertion boundary so regeneration never accumulates whitespace.
perl -0pi -e 's/\n+\z/\n/' "$before_path"

catalog=(
  chair chair_modern_cushion sofa coffee_table bookcase desk bed side_table
  floor_lamp floor_lamp_round table_lamp_square table_lamp_round ceiling_fan
  kitchen_island bar_stool kitchen_fridge kitchen_stove kitchen_sink
  kenney_kitchen_cabinet kitchen_blender toaster lounge_chair
  lounge_design_chair lounge_design_sofa lounge_sofa_corner lounge_sofa_ottoman
  table table_round table_cross table_glass rug_rectangle rug_round rug_square
  bathtub kenney_toilet kenney_bathroom_sink shower_round washer dryer
  cardboard_box_closed cardboard_box_open trashcan radio speaker speaker_small
  plant_small1 nature_bush nature_grass
)

{
  printf '%s\n' "$generated_start"
  printf '# 928 instances + 72 authored objects = exactly 1,000 renderable props.\n'
  for ((index = 0; index < 928; index++)); do
    column=$((index % 32))
    row=$((index / 32))
    catalog_index=$((index % ${#catalog[@]}))
    x=$(awk -v column="$column" 'BEGIN { printf "%.3f", 1.5 + column * 1.95 }')
    y=$(awk -v row="$row" 'BEGIN { printf "%.3f", 1.5 + row * 2.1 }')
    rotation=$(((index * 47 + row * 13) % 360))
    red=$((70 + (index * 37) % 186))
    green=$((70 + (index * 67) % 186))
    blue=$((70 + (index * 97) % 186))
    alpha=255
    if ((index % 19 == 0)); then alpha=176; fi
    elevation="0.000"
    if ((index % 23 == 0)); then elevation="0.350"; fi
    printf '\n[[objects]]\n'
    printf 'id = "generated_%04d"\n' "$((index + 1))"
    printf 'catalog_id = "%s"\n' "${catalog[$catalog_index]}"
    printf 'story = 0\n'
    printf 'position = [[%s, %s]]\n' "$x" "$y"
    printf 'elevation = %s\n' "$elevation"
    printf 'rotation = %d\n' "$rotation"
    printf 'tint = [%d, %d, %d, %d]\n' "$red" "$green" "$blue" "$alpha"
  done
  printf '%s\n\n' "$generated_end"
} > "$generated_path"

{
  cat "$before_path"
  cat "$generated_path"
  cat "$after_path"
} > "$work_dir/chaos_lot.toml"

mv "$work_dir/chaos_lot.toml" "$lot_path"
rm "$clean_path" "$before_path" "$after_path" "$generated_path"
rmdir "$work_dir"

printf 'Generated 928 deterministic instances in %s (1,000 total props).\n' "$lot_path"
