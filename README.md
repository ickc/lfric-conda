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

Early. See [`docs/proposal.md`](docs/proposal.md) for the full survey of what
Stage 1 contains, what conda-forge already provides, and what has to be packaged.

The short version: **conda-forge already has almost everything** — including
`psyclone`, `fparser`, `sci-fab`, `metomi-rose`, `cylc-flow`, `cylc-rose`, the
gfortran 14.3 toolchain, and `mpi_mpich_*` builds of `hdf5`/`libnetcdf`/
`netcdf-fortran`. The gap is:

| package | status |
|---|---|
| `xios` | to package — the hard one (FCM / `make_xios`) |
| `blitzpp` | to package (XIOS dep; the name `blitz` is taken by Blitz.js) |
| `rose-picker` | to package (trivial, `noarch: python`) |
| `yaxt` | exists on conda-forge, needs a `linux-aarch64` build |
| `shumlib` | to package (Stage 2 / apps tier) |
| `pfunit`, `gftl`, `gftl-shared`, `fargparse` | to package (unit tests only) |

Recipes are developed here and upstreamed to conda-forge one at a time.

## MVP-1

Build `lfric_core` from a `conda activate`d environment on `linux-aarch64`, with
MPI from conda-forge.

[`envs/lfric-env-mvp1.yaml`](envs/lfric-env-mvp1.yaml) is the base: every Stage-1
dependency conda-forge *already* has. It has been solved and built on Isambard 3
(Cray EX, Grace/aarch64), and a program doing `use mpi` + `use netcdf` compiles
and runs against it. The four gap packages above are what stand between that and
a working `lfric_core` build.

```console
$ micromamba create -n lfric-mvp1 -f envs/lfric-env-mvp1.yaml
$ micromamba activate lfric-mvp1
```

## Licence

The packaging in this repo is BSD-3-Clause (see [`LICENSE`](LICENSE)), matching
conda-forge feedstock convention. Each *packaged* project keeps its own upstream
licence, recorded in its recipe.
