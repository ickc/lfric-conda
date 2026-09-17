#!/usr/bin/env bash
# Common environment for the scripts. SOURCE this file; do not run it.
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

info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }
export -f info warn die 2>/dev/null || true
