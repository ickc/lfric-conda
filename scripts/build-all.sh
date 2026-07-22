#!/usr/bin/env bash
# scripts/build-all.sh [name...]
#
# Build every recipe (or just the named ones) in dependency order, into the local
# channel. The order comes from BUILD_ORDER in common.sh -- keep it authoritative
# there rather than duplicating it here.
#
#   bash scripts/build-all.sh              # everything, in order
#   bash scripts/build-all.sh blitzpp xios # just these, still in BUILD_ORDER order
set -euo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_here/common.sh"

wanted=("$@")
selected=()
for name in $BUILD_ORDER; do
  [ -f "$RECIPE_DIR/$name/recipe.yaml" ] || { info "skip '$name' (not written yet)"; continue; }
  if [ ${#wanted[@]} -eq 0 ]; then
    selected+=("$name")
  else
    for w in "${wanted[@]}"; do [ "$w" = "$name" ] && selected+=("$name"); done
  fi
done

[ ${#selected[@]} -gt 0 ] || die "nothing to build (BUILD_ORDER=$BUILD_ORDER)"

info "Building in order: ${selected[*]}"
for name in "${selected[@]}"; do
  bash "$_here/build-recipe.sh" "$name" || die "failed building '$name'"
done
echo "BUILD_ALL_OK"
