#!/usr/bin/env bash
set -euxo pipefail

# Kept close to conda-forge/yaxt-feedstock's build.sh so this stays an easy
# drop-in replacement once upstream builds linux-aarch64.
autoreconf -vfi

export CC=mpicc
export FC=mpifort

# yaxt's configure runs MPI programs to probe the implementation, so it needs a
# launcher. openmpi refuses to oversubscribe by default and will not run as root
# without an rsh agent override.
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
