#!/usr/bin/env bash
# scripts/build-recipe.sh <recipe-name> [extra rattler-build args...]
#
# Build ONE recipe into the local channel. This is the primitive every other
# build path composes: build-all.sh loops over it, and CI calls it per package.
#
#   bash scripts/build-recipe.sh rose-picker
#   bash scripts/build-recipe.sh xios --target-platform linux-aarch64
#
# Requires rattler-build on PATH (pixi provides it: `pixi run build <name>`).
set -euo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_here/common.sh"

[ $# -ge 1 ] || die "usage: $0 <recipe-name> [rattler-build args...]"
name="$1"; shift

recipe="$RECIPE_DIR/$name/recipe.yaml"
if [ ! -f "$recipe" ]; then
  have="$(find "$RECIPE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f ' 2>/dev/null)"
  die "no recipe at $recipe (have: ${have:-none})"
fi

command -v rattler-build >/dev/null 2>&1 \
  || die "rattler-build not on PATH. Install it: pixi install (then 'pixi run build $name'), or 'micromamba create -n rattler rattler-build'"

mkdir -p "$LOCAL_CHANNEL"

# The local channel is also an INPUT channel: later recipes depend on earlier
# ones (xios needs blitzpp), so it must be searched before conda-forge.
args=(
  --recipe "$recipe"
  --output-dir "$LOCAL_CHANNEL"
  -c "file://$LOCAL_CHANNEL"
)

# Extra read-only dependency channels. The local build-all flow leaves this empty
# and lets everything accumulate in LOCAL_CHANNEL; CI's per-package jobs instead
# restore each upstream package's channel from an artifact and point here (one
# dir per dep), so a package builds against exactly its declared dependencies.
# LFRIC_DEP_CHANNELS is a space-separated list of channel directories.
if [ -n "${LFRIC_DEP_CHANNELS:-}" ]; then
  for ch in $LFRIC_DEP_CHANNELS; do
    args+=(-c "file://$ch")
  done
fi

args+=(-c conda-forge)

# Base (common) variant config, then the per-OS overlay on top -- rattler-build
# merges them (variants/{linux,osx}.yaml carry the platform-specific pins).
[ -f "$VARIANT_CONFIG" ] && args+=(--variant-config "$VARIANT_CONFIG")
[ -n "${VARIANT_CONFIG_OS:-}" ] && [ -f "$VARIANT_CONFIG_OS" ] && args+=(--variant-config "$VARIANT_CONFIG_OS")

info "Building '$name' -> $LOCAL_CHANNEL"
rattler-build build "${args[@]}" "$@"
info "BUILD_OK $name"
