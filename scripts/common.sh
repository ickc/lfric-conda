#!/usr/bin/env bash
# Common environment for the build scripts. SOURCE this file; do not run it.
#
# Kept deliberately small and side-effect-light (env vars only). Configuration is
# explicit env vars with clear defaults -- no filesystem probing, no inference.
# Deeper rationale lives in docs/proposal.md.

# --- Repo root -------------------------------------------------------------
# pixi exports PIXI_PROJECT_ROOT; otherwise derive it from this file's path.
if [ -n "${PIXI_PROJECT_ROOT:-}" ]; then
  REPO_ROOT="$PIXI_PROJECT_ROOT"
else
  REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
fi
export REPO_ROOT

# --- Where built packages land ---------------------------------------------
# LOCAL_CHANNEL is a plain directory channel: rattler-build writes
# <subdir>/<pkg>.conda into it and it can be passed to any conda client with
# `-c file://$LOCAL_CHANNEL`. Gitignored; safe to delete and rebuild.
export LOCAL_CHANNEL="${LFRIC_CONDA_CHANNEL:-$REPO_ROOT/local-channel}"

# --- Recipe locations ------------------------------------------------------
export RECIPE_DIR="$REPO_ROOT/recipes"
export VARIANT_CONFIG="$REPO_ROOT/variants/conda_build_config.yaml"

# --- Build order -----------------------------------------------------------
# Dependency order, so build-all.sh can just walk the list. Leaf packages first.
# Keep this list authoritative: it is the project's roadmap in execution order.
export BUILD_ORDER="rose-picker blitzpp yaxt xios"

info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }
export -f info warn die 2>/dev/null || true
