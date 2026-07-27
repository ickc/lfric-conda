#!/usr/bin/env bash
# examples/science-suites/run-suite.sh -- run an LFRic science suite against the
# conda Stage-1 environment, the way a scientist does: with Cylc.
#
# THIS IS A SCIENCE-SUITE EXAMPLE. The core of this repo is the environment
# (Stage 1, recipes/). Running a real Rose/Cylc suite is one thing you do *with*
# it -- the fullest Stage-2 demonstration there is, because it exercises the whole
# environment: rose + cylc drive it, psyclone/rose-picker/fab build it, and
# mpich/XIOS/netCDF/HDF5/yaxt/shumlib run it.
#
# What this does:
#   1. Activates the environment (rose/cylc/psyclone + compilers on PATH), so the
#      `cylc` running the scheduler is the same one the tasks use.
#   2. Installs the (optional) cylc run-directory config via scripts/setup-cylc.sh.
#   3. Runs `cylc vip` (validate-install-play), injecting REPO_ROOT /
#      LFRIC_CONDA_ENV / ACTIVATE_ENV so every task re-activates the environment.
#
# Usage:   bash examples/science-suites/run-suite.sh <suite-id> [cylc vip args...]
#   e.g.   bash examples/science-suites/run-suite.sh u-dr932
#          bash examples/science-suites/run-suite.sh u-dr932 --no-detach
# Watch:   cylc tui <suite-id>   /   cylc workflow-state <suite-id>
# Clean:   cylc stop --now <suite-id>; cylc clean <suite-id> -y
#
# Env:
#   LFRIC_CONDA_ENV   environment to activate (default: the active one)
#   CYLC_PLATFORM     cylc platform for the tasks (default: localhost/background)
#   LFRIC_SUITE_CORES cores a task may use      (default: nproc)
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd -- "$_here/../.." && pwd)}"
export REPO_ROOT
SITE="$_here/site"

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "INFO: $*"; }

SUITE="${1:-}"
[ -n "$SUITE" ] || die "usage: run-suite.sh <suite-id> [cylc vip args...]  (e.g. u-dr932)"
shift || true
SUITE_DIR="$_here/$SUITE"
[ -d "$SUITE_DIR" ] || die "no such suite: $SUITE_DIR"

# 1. Activate. The scheduler is launched from this shell, and every task
#    re-activates independently via ACTIVATE_ENV -- but activating here is what
#    makes `cylc`/`rose` below the environment's own.
# shellcheck source=examples/science-suites/site/activate-env.sh
. "$SITE/activate-env.sh"
command -v cylc >/dev/null 2>&1 \
  || die "no 'cylc' on PATH after activation -- activate the environment first, or set LFRIC_CONDA_ENV"
command -v rose >/dev/null 2>&1 || die "no 'rose' on PATH after activation"
[ -n "${CONDA_PREFIX:-}" ] || die "no CONDA_PREFIX after activation"

info "env: $CONDA_PREFIX"
info "cylc $(cylc version 2>/dev/null) | rose $(rose version 2>/dev/null | awk '{print $2}') | psyclone $(psyclone --version 2>/dev/null | awk '{print $NF}')"

# The source must be staged: the suite's `extract` task reads the local mirrors
# offline, so a missing mirror fails there rather than here otherwise.
[ -d "$REPO_ROOT/vendor/lfric_apps" ] \
  || die "LFRic source not staged -- run: bash scripts/stage-sources.sh"

# 2. Cylc run-directory config (opt-in; idempotent).
bash "$REPO_ROOT/scripts/setup-cylc.sh" || die "setup-cylc.sh failed"

# 3. Launch. Pass the environment as an absolute PREFIX (not a name): a task's
#    clean shell may have no conda config at all, so a name would not resolve.
CORES="${LFRIC_SUITE_CORES:-$( (nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null) || echo 4)}"
info "cylc vip $SUITE_DIR --workflow-name $SUITE  (cores=$CORES, platform=${CYLC_PLATFORM:-localhost})"
exec cylc vip "$SUITE_DIR" \
  --workflow-name "$SUITE" \
  -S "REPO_ROOT='$REPO_ROOT'" \
  -S "LFRIC_CONDA_ENV='$CONDA_PREFIX'" \
  -S "ACTIVATE_ENV='$SITE/activate-env.sh'" \
  -S "CYLC_PLATFORM='${CYLC_PLATFORM:-localhost}'" \
  -S "CORES_PER_NODE=$CORES" \
  "$@"
