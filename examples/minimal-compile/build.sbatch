#!/bin/bash
#SBATCH --job-name=lfric-atm-conda
#SBATCH --partition=grace
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem-per-cpu=1600M
#SBATCH --time=02:00:00
#SBATCH --output=logs/lfric-atm-%j.out
#
# MINIMAL-COMPILE EXAMPLE on an Isambard 3 Grace compute node: compile lfric_atm
# against the conda environment. The counterpart of the Spack repo's
# examples/minimal-compile/build.sbatch. Submit from the repo root:
#
#   sbatch --export=ALL,LFRIC_CONDA_ENV=/path/to/env examples/minimal-compile/build.sbatch
#
# Prerequisites, on a LOGIN node (compute nodes are not expected to reach the
# network): the environment exists (micromamba create -p ... -f envs/lfric-env.yaml)
# and the source is staged + patched (scripts/stage-sources.sh, scripts/patch-all.sh).
# Resources as in the Spack repo: grace allocates 1600 MB per core, so this claims
# a full per-core share and scales with --cpus-per-task.
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1

# ---- Configuration --------------------------------------------------------
export LFRIC_CONDA_ENV="${LFRIC_CONDA_ENV:-lfric-env}"   # env NAME or PATH
export MAKE_JOBS="${MAKE_JOBS:-${SLURM_CPUS_PER_TASK:-24}}"
# Transient build tree on node-local disk ($LOCALDIR on Isambard), off Lustre.
export WORK_DIR="${WORK_DIR:-${LOCALDIR:-$PWD/output}/lfric_atm_build}"
export LOG="${LOG:-$PWD/logs/lfric-atm-make-${SLURM_JOB_ID:-local}.log}"
# ---------------------------------------------------------------------------

echo "host=$(hostname) jobid=${SLURM_JOB_ID:-?} cpus=${SLURM_CPUS_PER_TASK:-?} MAKE_JOBS=$MAKE_JOBS"
echo "  LFRIC_CONDA_ENV=$LFRIC_CONDA_ENV"
echo "  WORK_DIR=$WORK_DIR"

# build.sh sources scripts/lfric-env-activate.sh, which activates LFRIC_CONDA_ENV.
bash examples/minimal-compile/build.sh
