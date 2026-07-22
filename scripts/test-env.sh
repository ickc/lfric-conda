#!/usr/bin/env bash
# scripts/test-env.sh [env-yaml]
#
# Create the MVP-1 environment from envs/ (plus the local channel, so
# locally-built packages are picked up) and smoke-test the toolchain it exports:
# compile and run a Fortran program that does `use mpi` + `use netcdf`.
#
# This is the cheap integration check -- the conda analogue of `concretize.sh` +
# the minimal-compile example in ickc/lfric-env-isambard. It proves the thing
# that actually matters: `conda activate` alone gives a working LFRic toolchain.
#
#   bash scripts/test-env.sh
#   bash scripts/test-env.sh envs/lfric-env-mvp1.yaml
set -euo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_here/common.sh"

ENV_YAML="${1:-$REPO_ROOT/envs/lfric-env-mvp1.yaml}"
[ -f "$ENV_YAML" ] || die "no environment file at $ENV_YAML"
ENV_NAME="${LFRIC_CONDA_ENV_NAME:-lfric-conda-test}"

# micromamba is the reference client (conda/mamba work too; adjust MAMBA_EXE).
MAMBA_EXE="${MAMBA_EXE:-$(command -v micromamba || true)}"
[ -n "$MAMBA_EXE" ] || die "micromamba not on PATH (set MAMBA_EXE to your conda/mamba binary)"

chan_args=()
[ -d "$LOCAL_CHANNEL" ] && chan_args+=(-c "file://$LOCAL_CHANNEL")
chan_args+=(-c conda-forge)

info "Creating '$ENV_NAME' from $ENV_YAML"
"$MAMBA_EXE" create -n "$ENV_NAME" -y -f "$ENV_YAML" "${chan_args[@]}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/smoke.f90" <<'EOF'
program smoke
  use mpi
  use netcdf
  implicit none
  integer :: ierr, rank, nprocs
  call MPI_Init(ierr)
  call MPI_Comm_rank(MPI_COMM_WORLD, rank, ierr)
  call MPI_Comm_size(MPI_COMM_WORLD, nprocs, ierr)
  if (rank == 0) then
     print *, "MPI ranks      : ", nprocs
     print *, "netCDF version : ", trim(nf90_inq_libvers())
  end if
  call MPI_Finalize(ierr)
end program smoke
EOF

info "Toolchain exported by the environment:"
# Single-quoted on purpose: these must expand INSIDE the activated environment,
# not in this shell.
# shellcheck disable=SC2016
"$MAMBA_EXE" run -n "$ENV_NAME" bash -c '
  set -e
  echo "  FC=${FC:-<unset>}  CXX=${CXX:-<unset>}"
  for t in mpif90 mpic++ psyclone rose cylc fab; do
    printf "  %-10s %s\n" "$t" "$(command -v $t || echo MISSING)"
  done
  mpif90 --version | head -1
'

info "Compiling and running the smoke test"
"$MAMBA_EXE" run -n "$ENV_NAME" bash -c "
  set -e
  cd '$work'
  mpif90 -o smoke smoke.f90 -lnetcdff -lnetcdf
  echo COMPILE_OK
  mpiexec -n 2 ./smoke 2>/dev/null
"
echo "TEST_ENV_OK"
