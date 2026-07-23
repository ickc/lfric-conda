#!/usr/bin/env bash
# examples/science-suites/site/activate-env.sh -- the ACTIVATE_ENV a science-suite
# task SOURCES to put the conda Stage-1 environment on the toolchain.
#
# It is the analogue of the upstream suites' env_lfric/activate.sh, and of the
# same file in the sibling Spack repo -- with the one substitution this whole
# project is about:
#
#     Spack repo:  module use <prefix>/modulefiles && module load lfric-env/...
#     here:        conda activate <prefix>  (+ scripts/lfric-env-activate.sh)
#
# Like its Spack counterpart it is a THIN activator: it does not hand-roll the
# compiler/FFLAGS/LDFLAGS setup, because that is the environment's job (Stage 1) --
# it lives in ONE place, scripts/lfric-env-activate.sh, and both this file and the
# minimal-compile example source it. That is what "the suite cannot tell which
# mechanism built the environment" means in practice.
#
# It reads from the task environment (the suite injects them in flow.cylc's
# [[root]] init-script, rendered by run-suite.sh's `cylc vip -S`):
#   LFRIC_CONDA_ENV   prefix (or name) of the environment to activate
#   LFRIC_CONDA_EXE   optional: which client to activate with
#
# SOURCE this file; do not execute it. Keep it side-effect-light (env only) -- no
# Cylc config writing (that is run-suite.sh's job).

# Locate the repo: this file is at examples/science-suites/site/activate-env.sh.
# ACTIVATE_ENV is passed as an absolute path into the SOURCE repo, so this resolves
# to the repo even though the suite itself runs from its installed cylc-run copy.
_aenv_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
_aenv_repo="${PIXI_PROJECT_ROOT:-$(cd -- "$_aenv_here/../../.." && pwd)}"

# A science suite OWNS these: it builds from its own per-suite extracted tree
# ($SOURCE_ROOT/lfric_{apps,core}, pinned by its dependencies.yaml) and sets its
# own target platform / FPP / working dir. lfric-env-activate.sh only defaults
# them when unset, so the suite's values survive -- but be explicit about it here,
# because getting it wrong mixes two source trees (duplicate kernels, version-skewed
# modules) and is exactly the bug the Spack-side activator had to guard against.
# shellcheck source=scripts/lfric-env-activate.sh
. "$_aenv_repo/scripts/lfric-env-activate.sh" \
  || echo "WARN: activate-env.sh: Stage-1 environment not activated" >&2

unset _aenv_here _aenv_repo
hash -r 2>/dev/null || true
