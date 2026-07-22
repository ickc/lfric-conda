#!/usr/bin/env bash
set -euxo pipefail

# Kept close to conda-forge/yaxt-feedstock's build.sh so this stays an easy
# drop-in replacement once upstream builds linux-aarch64.
autoreconf -vfi

export CC=mpicc
export FC=mpifort

# yaxt's configure RUNS MPI programs to probe for known MPI defects, so it needs
# a launcher that actually works inside the build sandbox. On a normal machine it
# does; in a CI container it does not, and configure hard-fails with
#   checking if $PREFIX/bin/mpirun works... no
#   configure: error: unable to find a working MPI launch program
# Two settings make mpich launchable in a container: fork instead of ssh for
# process startup, and the tcp libfabric provider instead of probing for
# high-performance fabrics that do not exist there. Both are no-ops on a host
# where the default would have worked anyway, so they are set unconditionally
# rather than hidden behind a CI test.
export HYDRA_LAUNCHER=fork
export FI_PROVIDER="${FI_PROVIDER:-tcp}"

# openmpi refuses to oversubscribe by default and will not run as root without
# an rsh agent override.
#
# `mpi` is injected into the build environment by rattler-build from the `mpi`
# key in variants/conda_build_config.yaml, so it is set despite never being
# assigned in this file.
# shellcheck disable=SC2154
if [[ "${mpi}" == "openmpi" ]]; then
  export MPI_LAUNCH="${PREFIX}/bin/mpirun --oversubscribe"
  export OMPI_MCA_plm_rsh_agent=""
else
  export MPI_LAUNCH="${PREFIX}/bin/mpirun"
fi

configure_args=(
  --prefix="${PREFIX}"
  --with-mpi-root="${PREFIX}"
  --with-pic
)

# Whether MPI programs can be launched at all is a property of the SANDBOX, not
# of the recipe: it works on a normal host and on GitHub's arm64 runners, but is
# flaky on their x86 ones even with the settings above. Rather than keep guessing
# at launcher settings, probe once and adapt -- so the outcome is deterministic
# per environment and says which path it took.
#
# MPI_LAUNCH may carry arguments (openmpi adds --oversubscribe), so it must split.
# shellcheck disable=SC2086
if ${MPI_LAUNCH} -n 1 true >/dev/null 2>&1; then
  echo "INFO: MPI launcher works -- keeping yaxt's MPI-defect probes"
else
  echo "WARNING: cannot launch MPI programs in this sandbox (${MPI_LAUNCH})."
  echo "WARNING: configuring --without-regard-for-quality, which skips yaxt's"
  echo "WARNING: probes for known MPI defects, so no defect workarounds are"
  echo "WARNING: compiled in. That is an acceptable trade against conda-forge's"
  echo "WARNING: mpich/openmpi, which are known-good implementations."
  configure_args+=(--without-regard-for-quality)
fi

# configure hides the actual failure in config.log; surface it rather than
# leaving a bare 'error: unable to ...' with no context.
if ! ./configure "${configure_args[@]}"; then
  echo "=== tail of config.log ==="
  tail -n 100 config.log || true
  exit 1
fi

make -j "${CPU_COUNT:-2}" all
make install
