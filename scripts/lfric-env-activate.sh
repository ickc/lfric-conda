#!/usr/bin/env bash
# scripts/lfric-env-activate.sh -- THE STAGE-1 ACTIVATION CONTRACT. Source this.
#
# This is the conda analogue of scripts/lfric-env.lua in the sibling Spack repo
# (ickc/lfric-env-isambard) -- the one file that says what "the LFRic environment
# is active" means, so that Stage 2 cannot tell which mechanism produced it:
#
#     Spack repo:   module load lfric-env/<version>/<variant>   (Lmod, lfric-env.lua)
#     this repo:    source scripts/lfric-env-activate.sh        (conda activate + this)
#
# Everything below is either (a) something `conda activate` already does and we
# leave alone, or (b) something LFRic's build system requires to be spelled a
# particular way. Only (b) is here. When the `lfric-env` metapackage exists, this
# file's exports become its activate.d/ script and sourcing it becomes redundant
# -- which is the point of keeping it in ONE place rather than in each example.
#
# Usage (from an already-activated environment -- the normal case):
#     conda activate lfric-env && . scripts/lfric-env-activate.sh
# Usage (activate the environment too -- for a clean task shell, e.g. a Cylc job):
#     LFRIC_CONDA_ENV=lfric-env . scripts/lfric-env-activate.sh
#
# Inputs (all optional):
#   LFRIC_CONDA_ENV   env NAME or PATH to activate if none is active yet
#   LFRIC_CONDA_EXE   client to activate with (default: micromamba, mamba, conda)
#   LFRIC_VENDOR_DIR  staged LFRic source root (default $REPO_ROOT/vendor)
#
# Caller-owned variables are PRESERVED, never overwritten: APPS_ROOT_DIR,
# CORE_ROOT_DIR, PHYSICS_ROOT, LFRIC_TARGET_PLATFORM, FPP, WORKING_DIR. A science
# suite owns its own source tree and target platform, exactly as in the Spack
# repo's activate-env.sh; the defaults here are a convenience for the
# minimal-compile example and an interactive shell.

_lfric_env_warn() { echo "WARN: lfric-env-activate: $*" >&2; }

# --- 1. Make sure an environment is active ---------------------------------
# A Cylc job (or any clean login shell) starts with nothing activated. Activating
# from inside a sourced script needs the client's shell hook, because
# `conda activate` is a shell function, not a program.
_lfric_env_same() {
  # Same environment? Compare resolved paths when both are paths (CONDA_PREFIX
  # always is), else fall back to the leaf name for the `-n <name>` form. Getting
  # this wrong is not cosmetic: a needless re-activation resets conda's own
  # FFLAGS/LDFLAGS underneath us.
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  [ "$1" = "$2" ] && return 0
  if [ -d "$1" ] && [ -d "$2" ]; then
    [ "$(cd -- "$1" && pwd -P)" = "$(cd -- "$2" && pwd -P)" ] && return 0
  fi
  [ "$(basename -- "$1")" = "$(basename -- "$2")" ]
}

if [ -n "${LFRIC_CONDA_ENV:-}" ] && ! _lfric_env_same "${CONDA_PREFIX:-}" "$LFRIC_CONDA_ENV"; then
  _lfric_exe="${LFRIC_CONDA_EXE:-$(command -v micromamba || command -v mamba || command -v conda || true)}"
  if [ -z "$_lfric_exe" ]; then
    _lfric_env_warn "no conda client found; cannot activate '$LFRIC_CONDA_ENV' (set LFRIC_CONDA_EXE)"
  else
    # micromamba's hook is `shell hook -s bash`; conda's/mamba's is `shell.bash hook`.
    eval "$("$_lfric_exe" shell hook -s bash 2>/dev/null || "$_lfric_exe" shell.bash hook)" || true
    # Whichever hook ran defines its own activate function; the env may be a name
    # or a path -- both clients accept either here.
    for _lfric_act in micromamba mamba conda; do
      if command -v "$_lfric_act" >/dev/null 2>&1 &&
         "$_lfric_act" activate "$LFRIC_CONDA_ENV" 2>/dev/null; then
        break
      fi
    done
    [ -n "${CONDA_PREFIX:-}" ] || _lfric_env_warn "could not activate '$LFRIC_CONDA_ENV'"
    unset _lfric_act
  fi
  unset _lfric_exe
fi

if [ -z "${CONDA_PREFIX:-}" ]; then
  _lfric_env_warn "no CONDA_PREFIX -- activate the environment first, or set LFRIC_CONDA_ENV"
  # shellcheck disable=SC2317  # reached when this file is executed, not sourced
  return 1 2>/dev/null || exit 1
fi

# --- 2. Compilers, spelled the way LFRic dispatches on ----------------------
# LFRic picks its compiler flag file by the LEAF NAME of $FC / $CXX
# (lfric_core/infrastructure/build/fortran/<fc>.mk, cxx/<cxx>.mk). It ships
# mpif90.mk and mpic++.mk -- so conda's <arch>-conda-linux-gnu-gfortran (no .mk)
# and mpich's mpicxx alias (no mpicxx.mk) both fail. This is the single most
# load-bearing line in the file, and the Spack modulefile sets exactly the same
# pair for its from-source variant.
#
# conda's compiler activation has already set CXX to its native C++ driver, and
# GXX to the identically-configured g++-named one; capture GXX before overriding
# CXX, to derive MPICH_CXX below.
_lfric_gxx="${GXX:-}"

export FC=mpif90
export LDMPI=mpif90
export CXX=mpic++

# cxx/mpic++.mk identifies the C++ backend from the FIRST WORD of `mpic++
# --version` and requires it to contain "g++". conda's mpic++ wraps the
# "c++"-named driver (<arch>-conda-linux-gnu-c++), which echoes that program name
# -- no "g++" in it. gfortran needs no equivalent because it always prints "GNU
# Fortran". Point the wrapper at the identically-configured g++-named driver (same
# gcc, so ABI-safe). Derived from conda's own CXX, so it stays arch-independent.
# (patches/11-lfric_core-mpicxx-patch.sh makes the .mk tolerant too; both are kept
# because the patch only reaches source we staged, while this reaches any tree.)
#
# GXX is conda's own g++-named driver, so no string surgery on CXX is needed --
# and unlike deriving it from CXX, reading GXX stays correct when this file is
# sourced twice (by then CXX is our own mpic++).
if [ -z "${MPICH_CXX:-}" ]; then
  if [ -n "$_lfric_gxx" ]; then
    export MPICH_CXX="$_lfric_gxx"
  elif [ -n "${CONDA_TOOLCHAIN_HOST:-}" ] && [ -x "$CONDA_PREFIX/bin/$CONDA_TOOLCHAIN_HOST-g++" ]; then
    export MPICH_CXX="$CONDA_PREFIX/bin/$CONDA_TOOLCHAIN_HOST-g++"
  else
    _lfric_env_warn "no GXX/CONDA_TOOLCHAIN_HOST -- MPICH_CXX unset; lfric_core's cxx/mpic++.mk may not recognise the C++ backend"
  fi
fi
unset _lfric_gxx

# LFRic preprocesses Fortran with a traditional-mode cpp.
export FPP="${FPP:-cpp -traditional-cpp}"

# Which flag file set to build with. meto-spice is the generic GNU/Linux one and
# is what the Spack modulefile defaults to as well.
export LFRIC_TARGET_PLATFORM="${LFRIC_TARGET_PLATFORM:-meto-spice}"

# --- 3. Where the environment's headers and libraries are -------------------
# `mpif90` already injects $CONDA_PREFIX/{include,lib}, but LFRic's Makefiles read
# FFLAGS/LDFLAGS directly (that is how XIOS/yaxt/netCDF .mod files and .a/.so are
# found), so spell them out. PREPEND to any inherited value, exactly as the
# modulefile's pushenv does, so the environment's own headers win over a caller's.
#
# Adding each flag only when absent keeps this file safe to source repeatedly --
# which it is, since a Cylc suite sources it once per task and an interactive user
# may source it again after `conda activate`.
_lfric_env_prepend() {  # <varname> <flags...>
  local var="$1"; shift
  local cur="${!var:-}" f
  for f in "$@"; do
    case " $cur " in *" $f "*) continue ;; esac
    cur="$f${cur:+ $cur}"
  done
  export "$var=$cur"
}
_lfric_env_prepend FFLAGS "-I$CONDA_PREFIX/include"
_lfric_env_prepend LDFLAGS "-L$CONDA_PREFIX/lib" "-Wl,-rpath=$CONDA_PREFIX/lib"

# lfric_apps links -lshum from $SHUMLIB_ROOT/{include,lib}; the shumlib package
# installs into the environment prefix, so that is the root.
export SHUMLIB_ROOT="$CONDA_PREFIX"

# --- 4. Runtime -------------------------------------------------------------
# HDF5 1.10+ flock()s files it creates; Lustre (and some CI filesystems) reject
# that, so XIOS's nc_create() of a NetCDF-4 output aborts with "Permission denied"
# after leaving a 0-byte file -- the model integrates fine, it just cannot write
# diagnostics. Disabling HDF5's own locking is the standard remedy and is safe
# here (Cylc serialises task access to these paths). Honour any value already set.
export HDF5_USE_FILE_LOCKING="${HDF5_USE_FILE_LOCKING:-FALSE}"

# --- 5. Source-tree defaults (caller-owned; never overwritten) --------------
# The Spack modulefile sets these to its vendored trees; the conda equivalent is
# this repo's staged vendor/. A science suite sets its own (its per-suite
# extracted tree) BEFORE sourcing this, and those values are kept.
_lfric_env_repo="${REPO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
_lfric_env_vendor="${LFRIC_VENDOR_DIR:-$_lfric_env_repo/vendor}"
export APPS_ROOT_DIR="${APPS_ROOT_DIR:-$_lfric_env_vendor/lfric_apps}"
export CORE_ROOT_DIR="${CORE_ROOT_DIR:-$_lfric_env_vendor/lfric_core}"
export PHYSICS_ROOT="${PHYSICS_ROOT:-$_lfric_env_vendor/physics}"
unset _lfric_env_repo _lfric_env_vendor

# PSyclone and the LFRic build write .pyc files into the source tree otherwise.
export PYTHONDONTWRITEBYTECODE=1

# Informational marker: which prefix this contract was last applied for. Cheap way
# for a script (or a person) to check that Stage 1 is active and which env it is.
export LFRIC_ENV_ACTIVE="$CONDA_PREFIX"
unset -f _lfric_env_warn _lfric_env_same _lfric_env_prepend
hash -r 2>/dev/null || true
