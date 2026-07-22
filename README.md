# lfric-conda

Conda packages for the **LFRic Stage-1 environment** — an independent way to
bootstrap the environment that Met Office LFRic science workflows build and run
against.

## What this is

LFRic is delivered in two stages:

- **Stage 1** — the environment: compilers, MPI, parallel netCDF/HDF5, XIOS,
  PSyclone, rose/cylc, and the rest of the toolchain.
- **Stage 2** — scientists bring Fortran source and drive it with cylc/rose to
  compile and run a workflow.

Stage 1 is currently delivered by [Spack][spack-repo]. **This repo delivers the
same Stage-1 environment via conda instead**, so an end user runs

```console
$ conda activate lfric-env
```

and can then perform any Stage-2 activity. Which mechanism produced the
environment must make no difference to Stage 2 — so the conda environment ships
the compilers too, not just the runtime libraries.

[spack-repo]: https://github.com/ickc/lfric-env-isambard

## Status

See [`docs/proposal.md`](docs/proposal.md) for the full survey of what Stage 1
contains, what conda-forge already provides, and what has to be packaged.

The short version: **conda-forge already has almost everything** — including
`psyclone`, `fparser`, `sci-fab`, `metomi-rose`, `cylc-flow`, `cylc-rose`, the
gfortran 14.3 toolchain, and `mpi_mpich_*` builds of `hdf5`/`libnetcdf`/
`netcdf-fortran`. The gap, and where it stands:

| package | status |
|---|---|
| `xios` | ✅ packaged — the hard one (FCM / `make_xios`) |
| `blitzpp` | ✅ packaged (XIOS dep; the name `blitz` is taken by Blitz.js) |
| `rose-picker` | ✅ packaged (`noarch: python`) |
| `yaxt` | ✅ packaged as an interim mirror; upstream needs a `linux-aarch64` build |
| `shumlib` | to package (apps tier) |
| `pfunit`, `gftl`, `gftl-shared`, `fargparse` | to package (unit tests only) |

All four build in CI on `linux-64` and `linux-aarch64`. Nothing has been
upstreamed to conda-forge yet — see [Upstreaming](#upstreaming).

## MVP-1

Build `lfric_core` from a `conda activate`d environment on `linux-aarch64`, with
MPI from conda-forge.

[`envs/lfric-env-mvp1.yaml`](envs/lfric-env-mvp1.yaml) is that environment.
Because the four packages above are not on conda-forge yet, it currently needs
the local channel:

```console
$ bash scripts/build-all.sh                 # populates ./local-channel
$ bash scripts/test-env.sh                  # creates the env and checks it
```

`scripts/test-env.sh` is the integration check. On Isambard 3 (Cray EX,
Grace/aarch64) it currently reports:

```
GNU Fortran (conda-forge gcc 14.3.0-19) 14.3.0
COMPILE_OK
 MPI ranks      :            2
 netCDF version : 4.10.0
  lib/libxios.a          present     include/xios.mod    present
  lib/libyaxt.so         present     include/yaxt.mod    present
  rose_picker / psyclone / fab       on PATH
MODULES_OK
TEST_ENV_OK
```

`MODULES_OK` is the one worth calling out: it compiles `use xios` + `use yaxt`
with the environment's *own* gfortran. gfortran can only read module files
written by its own generation, so that check is what proves the whole stack —
conda-forge's Fortran packages and the ones built here — agrees on one compiler.

## Upstreaming

Recipes are developed here and upstreamed to conda-forge one at a time, easiest
first, so the process is learned on cheap PRs:

1. `rose-picker` — trivial `noarch: python`
2. `yaxt` — **not a new recipe**: the feedstock exists and its recipe has no
   aarch64 skip, it just never enabled the platform in `conda-forge.yml`. A
   one-line `provider: {linux_aarch64: azure}` migration PR. That it builds here
   on aarch64 is the evidence nothing else is in the way.
3. `blitzpp`
4. `gftl`, `gftl-shared`, `fargparse`, `pfunit`
5. `shumlib` — approach ACCESS-NRI first, who already maintain a recipe
6. `xios` — last; hardest; may stay in-house longest

The local channel means none of this blocks development.

## Licence

The packaging in this repo is BSD-3-Clause (see [`LICENSE`](LICENSE)), matching
conda-forge feedstock convention. Each *packaged* project keeps its own upstream
licence, recorded in its recipe.
