#!/bin/bash
#SBATCH --job-name=lfric-suite-conda
#SBATCH --partition=grace
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem-per-cpu=1600M
#SBATCH --time=03:00:00
#SBATCH --output=logs/suite-%j.out
#
# SCIENCE-SUITE EXAMPLE on an Isambard 3 Grace compute node: run a Rose/Cylc suite
# end to end (extract -> build -> mesh -> run the model) against the conda
# environment, with the cylc scheduler in the foreground so the job's exit status
# is the workflow's. Submit from the repo root:
#
#   sbatch --export=ALL,LFRIC_CONDA_ENV=/path/to/env examples/science-suites/run-suite.sbatch
#
# Extra arguments go to `cylc vip`. Without any, u-dr932 runs at the full size it
# was validated at on Isambard 3 (C48_MG, 24 ranks, 1 day); the defaults in its
# rose-suite.conf are the CI-sized ones. For example, the CI size:
#
#   sbatch --export=ALL,LFRIC_CONDA_ENV=... examples/science-suites/run-suite.sbatch u-dr932
#
# Prerequisites, on a LOGIN node: the environment exists and the LFRic source is
# staged + patched (see README). Every task runs on this one node through cylc's
# `localhost` platform; 32 cores cover the 24 model ranks, the XIOS server and the
# build. Single node, so mpich's UCX is pinned to shared memory, as in CI.
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1

export LFRIC_CONDA_ENV="${LFRIC_CONDA_ENV:-lfric-env}"   # env NAME or PATH
export LFRIC_SUITE_CORES="${LFRIC_SUITE_CORES:-${SLURM_CPUS_PER_TASK:-32}}"
export UCX_TLS="${UCX_TLS:-sm,self}"

if [ "$#" -eq 0 ]; then
  set -- u-dr932 \
    -S "LFRIC_RES='C48_MG'" -S "TOTAL_RANKS_REQ=24" \
    -S "EXPT_RUNLEN='P1D'" -S "EXPT_RESUB='P1D'"
fi

echo "host=$(hostname) jobid=${SLURM_JOB_ID:-?} cpus=${SLURM_CPUS_PER_TASK:-?}"
echo "  LFRIC_CONDA_ENV=$LFRIC_CONDA_ENV  args: $*"

bash examples/science-suites/run-suite.sh "$@" --no-detach
