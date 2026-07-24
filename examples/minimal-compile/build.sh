#!/usr/bin/env bash
# examples/minimal-compile/build.sh -- compile the lfric_atm science target against
# the conda-provided Stage-1 environment. The conda analogue of
# examples/minimal-compile/build.sh in ickc/lfric-env-isambard.
#
# This is the smallest STAGE-2 example: it demonstrates that once the environment
# is provided by conda instead of Spack/Lmod, an end user compiles LFRic exactly
# the same way. No science run -- see examples/science-suites/ for that.
#
# Prerequisites:
#   1. an environment (envs/lfric-env.yaml -- see README / scripts/test-env.sh)
#   2. the LFRic source staged and patched:
#        bash scripts/stage-sources.sh && bash scripts/patch-all.sh
#
# Usage:
#   micromamba run -n lfric-env bash examples/minimal-compile/build.sh
# or from an activated env:
#   conda activate lfric-env && bash examples/minimal-compile/build.sh
#
# Inputs (all have defaults):
#   LFRIC_VENDOR_DIR   staged source root         (default: $REPO_ROOT/vendor)
#   LFRIC_APPS_ROOT    = $LFRIC_VENDOR_DIR/lfric_apps
#   LFRIC_CORE_ROOT    = $LFRIC_VENDOR_DIR/lfric_core
#   PHYSICS_ROOT       = $LFRIC_VENDOR_DIR/physics
#   LFRIC_SRC_REPO     use ANOTHER repo's vendored source instead (e.g. the
#                      sibling Spack repo) -- sets the three above from it
#   WORK_DIR           build working dir          (default: output/lfric_atm_build)
#   MAKE_JOBS          parallel compile jobs      (default: nproc, capped at 16)
set -uo pipefail

info() { echo "INFO: $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd -- "$_here/../.." && pwd)"
export REPO_ROOT

# --- Stage 1: activate the environment --------------------------------------
# The whole toolchain contract lives in ONE place -- scripts/lfric-env-activate.sh,
# the conda analogue of the Spack repo's scripts/lfric-env.lua. Sourcing it here is
# what makes this example a faithful "what an end user does" demonstration: it sets
# FC/CXX/LDMPI to the leaf names LFRic dispatches its flag files on, puts the
# environment's include/lib on FFLAGS/LDFLAGS, and points SHUMLIB_ROOT at the
# prefix. Set LFRIC_CONDA_ENV to have it activate the environment too.
# shellcheck source=scripts/lfric-env-activate.sh
. "$REPO_ROOT/scripts/lfric-env-activate.sh" \
  || die "could not activate the Stage-1 environment"

info "Toolchain: FC=$FC CXX=$CXX -- $($FC --version 2>/dev/null | head -1)"

# --- LFRic source -----------------------------------------------------------
# Staged by scripts/stage-sources.sh + patched by scripts/patch-all.sh. Pointing
# LFRIC_SRC_REPO at the sibling Spack repo reuses ITS vendored source instead --
# identical source, so the comparison isolates the environment (that is how this
# example was first proven, before this repo staged its own).
if [ -n "${LFRIC_SRC_REPO:-}" ]; then
  APPS_ROOT_DIR="${LFRIC_APPS_ROOT:-$LFRIC_SRC_REPO/vendor/lfric_apps}"
  CORE_ROOT_DIR="${LFRIC_CORE_ROOT:-$LFRIC_SRC_REPO/vendor/lfric_core}"
  export PHYSICS_ROOT="${PHYSICS_ROOT:-$LFRIC_SRC_REPO/vendor/physics}"
else
  # lfric-env-activate.sh already defaulted these to $LFRIC_VENDOR_DIR/...
  APPS_ROOT_DIR="${LFRIC_APPS_ROOT:-$APPS_ROOT_DIR}"
  CORE_ROOT_DIR="${LFRIC_CORE_ROOT:-$CORE_ROOT_DIR}"
fi
export APPS_ROOT_DIR CORE_ROOT_DIR

[ -f "$APPS_ROOT_DIR/build/local_build.py" ] \
  || die "local_build.py not found under $APPS_ROOT_DIR/build -- stage the source first: bash scripts/stage-sources.sh && bash scripts/patch-all.sh"
[ -d "$CORE_ROOT_DIR/infrastructure/build" ] \
  || die "lfric_core not found at $CORE_ROOT_DIR -- run: bash scripts/stage-sources.sh"
for d in casim jules socrates ukca; do
  [ -d "$PHYSICS_ROOT/$d" ] \
    || die "physics source '$d' not staged under $PHYSICS_ROOT -- run: bash scripts/stage-sources.sh"
done
# The offline-source patch is what stops local_build.py cloning mid-build; without
# it the build silently reaches the network and the pinned refs stop meaning anything.
grep -q "PATCHED (lfric-env-isambard)" "$APPS_ROOT_DIR/build/extract/get_git_sources.py" 2>/dev/null \
  || die "source tree is not patched -- run: bash scripts/patch-all.sh"

PSYCLONE_TRANSFORMATION="${PSYCLONE_TRANSFORMATION:-minimum}"
# Default to the machine's core count (capped: LFRic's link steps are memory-hungry,
# and a 4-vCPU CI runner must not be told to run 16 compilers).
_ncpu="$( (nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null) || echo 4)"
MAKE_JOBS="${MAKE_JOBS:-$(( _ncpu > 16 ? 16 : _ncpu ))}"
# Default the (large, transient) build dir into the repo's gitignored output/.
WORK_DIR="${WORK_DIR:-$REPO_ROOT/output/lfric_atm_build}"
LOG="${LOG:-$WORK_DIR/lfric_atm-make.log}"
mkdir -p "$WORK_DIR" || die "cannot create WORK_DIR=$WORK_DIR"

# Keep the shared physics_scratch clean between runs (as the Spack example does).
rm -rf "$APPS_ROOT_DIR/applications/lfric_atm/physics_scratch" \
       "$APPS_ROOT_DIR/applications/lfric_atm/working/physics_scratch" 2>/dev/null || true

info "Building lfric_atm (PSYCLONE_TRANSFORMATION=$PSYCLONE_TRANSFORMATION, -j $MAKE_JOBS)"
info "  source: $APPS_ROOT_DIR (core: $CORE_ROOT_DIR)"
info "  work:   $WORK_DIR"
( cd "$APPS_ROOT_DIR" && python build/local_build.py lfric_atm \
    -c "$CORE_ROOT_DIR" -w "$WORK_DIR" -j "$MAKE_JOBS" -t build \
    -p "$PSYCLONE_TRANSFORMATION" ) |& tee "$LOG"
rc="${PIPESTATUS[0]}"
[ "$rc" -eq 0 ] || die "local_build.py failed for lfric_atm (rc=$rc). See $LOG"

APP_BIN="$APPS_ROOT_DIR/applications/lfric_atm/bin/lfric_atm"
[ -x "$APP_BIN" ] || die "executable not found at $APP_BIN"
info "Built: $APP_BIN"
echo "LFRIC_ATM_OK"
