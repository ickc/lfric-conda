#!/usr/bin/env bash
# examples/minimal-compile/build.sh -- compile the lfric_atm science target against
# the conda-provided Stage-1 environment. The conda analogue of
# examples/minimal-compile/build.sh in ickc/lfric-env-isambard.
#
# This is the STAGE-2 proof: it demonstrates that once the environment is provided
# by conda instead of Spack/Lmod, an end user compiles LFRic exactly the same way.
# It reuses the LFRic *source* vendored in the sibling Spack repo (identical source;
# only the environment differs), so nothing here re-stages LFRic.
#
# Usage (env must be created first -- see scripts/test-env.sh / envs/):
#   micromamba run -n lfric-conda-stage2 bash examples/minimal-compile/build.sh
# or from an activated env:
#   conda activate lfric-conda-stage2 && bash examples/minimal-compile/build.sh
#
# Inputs (all have defaults):
#   LFRIC_SRC_REPO   sibling Spack repo holding the vendored LFRic source
#   LFRIC_APPS_ROOT  = $LFRIC_SRC_REPO/vendor/lfric_apps
#   LFRIC_CORE_ROOT  = $LFRIC_SRC_REPO/vendor/lfric_core
#   PHYSICS_ROOT     = $LFRIC_SRC_REPO/vendor/physics
#   WORK_DIR         build working dir (default: a scratch dir outside the source)
#   MAKE_JOBS        parallel compile jobs (default 16)
set -uo pipefail

info() { echo "INFO: $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

[ -n "${CONDA_PREFIX:-}" ] || die "no CONDA_PREFIX -- activate the env first (micromamba run -n <env> ... / conda activate <env>)"

# --- The lfric-env contract -------------------------------------------------
# This block is exactly what the future `lfric-env` conda metapackage's
# activate.d/ script must export -- the conda analogue of scripts/lfric-env.lua in
# the Spack repo. `conda activate` alone gives the toolchain, but LFRic needs it
# spelled a particular way:
#
#  * FC/LDMPI/CXX by the LEAF NAME LFRic dispatches its flag files on
#    (infrastructure/build/fortran/<fc>.mk, cxx/<cxx>.mk): mpif90.mk and mpic++.mk
#    exist, so FC=mpif90 and CXX=mpic++ -- NOT conda's aarch64-conda-linux-gnu-*
#    (no such .mk) nor mpich's mpicxx alias (no mpicxx.mk). This is the FC leaf-name
#    trap flagged in docs/proposal.md, confirmed here.
#  * FFLAGS/LDFLAGS carrying the env's own include/lib so XIOS/yaxt/netCDF .mod
#    files and .a/.so resolve. mpif90 already injects $CONDA_PREFIX/{include,lib},
#    but LFRic's Makefiles read FFLAGS/LDFLAGS directly, so set them explicitly.
#  * SHUMLIB_ROOT for lfric_apps' -I$SHUMLIB_ROOT/include -L$SHUMLIB_ROOT/lib -lshum
#    (shumlib installs into $CONDA_PREFIX/{include,lib}).
#  * FPP + LFRIC_TARGET_PLATFORM, matching the Spack modulefile's defaults.
# conda's compiler activation has already set CXX to its native C++ driver
# (aarch64-conda-linux-gnu-c++); capture it before we override CXX below.
_conda_cxx="${CXX:-}"

export FC=mpif90
export LDMPI=mpif90
export CXX=mpic++
# LFRic's cxx/mpic++.mk identifies the C++ backend from `mpic++ --version`'s first
# word and requires it to contain "g++". conda's mpic++ wraps the "c++"-named
# driver (aarch64-conda-linux-gnu-c++), whose --version echoes that program name
# (no "g++") -- unlike gfortran, which always prints "GNU Fortran", which is why
# FC=mpif90 needs no such help. Point mpic++ at the identically-configured
# g++-named driver (same gcc 14.3, so ABI-safe) via MPICH_CXX so the check passes.
# Derived from conda's own CXX, so it is arch-independent.
if [ -n "$_conda_cxx" ] && [ "${_conda_cxx%c++}" != "$_conda_cxx" ]; then
  export MPICH_CXX="${_conda_cxx%c++}g++"
fi
export FPP="cpp -traditional-cpp"
export LFRIC_TARGET_PLATFORM="${LFRIC_TARGET_PLATFORM:-meto-spice}"
export FFLAGS="-I$CONDA_PREFIX/include ${FFLAGS:-}"
export LDFLAGS="-L$CONDA_PREFIX/lib -Wl,-rpath=$CONDA_PREFIX/lib ${LDFLAGS:-}"
export SHUMLIB_ROOT="$CONDA_PREFIX"

info "Toolchain: FC=$FC CXX=$CXX -- $($FC --version 2>/dev/null | head -1)"

# --- LFRic source (reused from the sibling Spack repo) ----------------------
LFRIC_SRC_REPO="${LFRIC_SRC_REPO:-/lfs1i3/scratch/u35v/khcheung.u35v/git/lfric-env-isambard}"
APPS_ROOT_DIR="${LFRIC_APPS_ROOT:-$LFRIC_SRC_REPO/vendor/lfric_apps}"
CORE_ROOT_DIR="${LFRIC_CORE_ROOT:-$LFRIC_SRC_REPO/vendor/lfric_core}"
export PHYSICS_ROOT="${PHYSICS_ROOT:-$LFRIC_SRC_REPO/vendor/physics}"
export PYTHONDONTWRITEBYTECODE=1

[ -f "$APPS_ROOT_DIR/build/local_build.py" ] || die "local_build.py not found under $APPS_ROOT_DIR/build (is $LFRIC_SRC_REPO the Spack repo with vendored LFRic source, patched via patch-all.sh?)"
for d in casim jules socrates ukca; do
  [ -e "$PHYSICS_ROOT/$d/.git" ] || die "physics submodule '$d' not initialised under $PHYSICS_ROOT"
done

PSYCLONE_TRANSFORMATION="${PSYCLONE_TRANSFORMATION:-minimum}"
MAKE_JOBS="${MAKE_JOBS:-16}"
# Default the (large, transient) build dir into the conda repo's gitignored
# output/, which is on the same writable scratch as the repo -- rather than
# guessing the scratch path layout.
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
CONDA_REPO_ROOT="$(cd -- "$_here/../.." && pwd)"
WORK_DIR="${WORK_DIR:-$CONDA_REPO_ROOT/output/lfric_atm_build}"
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
