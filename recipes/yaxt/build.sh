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
if [[ "${mpi}" == "openmpi" ]]; then
  export MPI_LAUNCH="${PREFIX}/bin/mpirun --oversubscribe"
  export OMPI_MCA_plm_rsh_agent=""
else
  export MPI_LAUNCH="${PREFIX}/bin/mpirun"
fi

./configure \
  --prefix="${PREFIX}" \
  --with-mpi-root="${PREFIX}" \
  --with-pic

make -j "${CPU_COUNT:-2}" all
make install
