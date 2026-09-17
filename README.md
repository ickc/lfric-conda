# lfric-conda

The **LFRic Stage-1 environment**, assembled from conda-forge packages — an
independent way to bootstrap the environment that Met Office LFRic science
workflows build and run against.

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

**Everything the environment needs is on conda-forge.** Most of it always was —
`psyclone`, `fparser`, `sci-fab`, `metomi-rose`, `cylc-flow`, `cylc-rose`, the
GNU toolchain, and `mpi_mpich_*` builds of `hdf5`/`libnetcdf`/`netcdf-fortran`.
The gap was packaged in this repo first and then upstreamed; each package now
lives on its own feedstock, built for `linux-64`, `linux-aarch64`, `osx-64` and
`osx-arm64`:

| package | feedstock |
|---|---|
| `xios` | [conda-forge/xios-feedstock](https://github.com/conda-forge/xios-feedstock) — the hard one (FCM / `make_xios`) |
| `blitzpp` | [conda-forge/blitzpp-feedstock](https://github.com/conda-forge/blitzpp-feedstock) (XIOS dep; the name `blitz` is taken by Blitz.js) |
| `rose-picker` | [conda-forge/rose-picker-feedstock](https://github.com/conda-forge/rose-picker-feedstock) (`noarch: python`) |
| `yaxt` | [conda-forge/yaxt-feedstock](https://github.com/conda-forge/yaxt-feedstock) — existing feedstock; gained `linux-aarch64`/`osx-arm64` and the opt-in `idxtype_long` (64-bit `Xt_int`) build LFRic requires |
| `shumlib` | [conda-forge/shumlib-feedstock](https://github.com/conda-forge/shumlib-feedstock) (apps tier — `lfric_apps` links `-lshum`) |
| `gftl`, `gftl-shared`, `fargparse`, `pfunit` | [gftl](https://github.com/conda-forge/gftl-feedstock), [gftl-shared](https://github.com/conda-forge/gftl-shared-feedstock), [fargparse](https://github.com/conda-forge/fargparse-feedstock), [pfunit](https://github.com/conda-forge/pfunit-feedstock) (unit-test tier) |

So this repo no longer builds packages. What is left here is the part no
feedstock can own: the environment definition, the activation contract, and the
Stage-2 examples that prove the two add up to a working LFRic environment. See
[`docs/platform-coverage.md`](docs/platform-coverage.md) for the per-package
platform policy and why Windows is out of scope, and
[`docs/proposal.md`](docs/proposal.md) for the original survey.

**Stage 2 works, and is tested:** both Stage-2 examples run against this
environment in CI on `linux-64` and `linux-aarch64` — the science target
`lfric_atm` compiles and links against it, and a real Rose/Cylc science suite runs
end to end on it (extract → build → mesh → **run the model**). See
[Stage 2](#stage-2--using-the-environment).

**Is it the same environment Spack gives you?** Yes, with three intended
differences (the MPI stack, `foxml`, and gcc 15.3 instead of 14.3) — audited
package by package and variable by variable in
[`docs/stage1-parity.md`](docs/stage1-parity.md).

## The environment

[`envs/lfric-env.yaml`](envs/lfric-env.yaml) is the full Stage-1 environment: one
spec per direct dependency of the Spack repo's `lfric-apps-isambard` bundle, all
from conda-forge:

```console
$ micromamba create -n lfric-env -f envs/lfric-env.yaml
$ bash scripts/test-env.sh                  # creates the env and smoke-tests it
```

(The narrower [`lfric-env-mvp1`](envs/lfric-env-mvp1.yaml) /
[`lfric-env-mvp2`](envs/lfric-env-mvp2.yaml) tiers — `lfric_core` only, and the
apps tier without the unit-test packages — are kept as the minimum each layer
needs.)

`scripts/test-env.sh` is the integration check. On Isambard 3 (Cray EX,
Grace/aarch64) it currently reports:

```
GNU Fortran (conda-forge gcc 15.3.0-5) 15.3.0
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

## Stage 2 — using the environment

Stage 2 needs LFRic *source*, which is not part of the environment. Both this repo
and the Spack repo pin the same six MetOffice repos at the same refs and apply the
same patches, so a comparison isolates the environment:

```console
$ bash scripts/stage-sources.sh   # clone the pins in sources.yaml into vendor/
$ bash scripts/patch-all.sh       # apply patches/ (offline sources, vn3.2 fixes)
```

There are two examples, both run in CI on `linux-64` and `linux-aarch64`:

**1. Compile a science target** —
[`examples/minimal-compile/build.sh`](examples/minimal-compile/build.sh) builds the
apps-tier target `lfric_atm` (~98 MB, linking the env's
`yaxt`/`netcdf`/`mpich`/`hdf5`):

```console
$ micromamba create -n lfric-env -f envs/lfric-env.yaml
$ micromamba run -n lfric-env bash examples/minimal-compile/build.sh
...
LFRIC_ATM_OK
```

**2. Run a real science suite** —
[`examples/science-suites/`](examples/science-suites/README.md) runs the Rose/Cylc
suite `u-dr932` (GungHo hot-Jupiter forcing) the way a scientist does: `cylc`
schedules extract → build → mesh → run, `rose` materialises the namelists, and the
model integrates under `mpiexec`.

```console
$ micromamba run -n lfric-env bash examples/science-suites/run-suite.sh u-dr932
```

This is the strongest Stage-2 evidence there is, because it exercises every layer
of the environment at once — rose/cylc drive it, psyclone/rose-picker/fab build it,
and mpich/XIOS/netCDF/HDF5/yaxt/shumlib run it.

### The activation contract

[`scripts/lfric-env-activate.sh`](scripts/lfric-env-activate.sh) is the conda
analogue of the Spack repo's `scripts/lfric-env.lua`: the single place that says
what "the LFRic environment is active" means, sourced by both examples and destined
to become the future `lfric-env` metapackage's `activate.d/`. Two of its exports
are non-obvious and were only found by compiling:

- **`FC=mpif90 CXX=mpic++`** — LFRic dispatches its compiler flag files by the
  *leaf name* of the compiler (`fortran/mpif90.mk`, `cxx/mpic++.mk`), so conda's
  `aarch64-conda-linux-gnu-*` names do not work.
- **`MPICH_CXX=$GXX`** — `cxx/mpic++.mk` identifies the C++ backend from the first
  word of `mpic++ --version` and requires it to contain `g++`. conda's `mpic++`
  wraps the `c++`-named driver, so point it at the identically-configured
  `g++`-named one (same gcc, ABI-safe). `FC` needs no equivalent because
  `gfortran --version` always prints "GNU Fortran".

## Upstreaming

Done. The recipes were developed here, then upstreamed through
[staged-recipes](https://github.com/conda-forge/staged-recipes) (and, for `yaxt`,
conda-forge/yaxt-feedstock#6), and the in-repo copies were removed so they cannot
drift from the feedstocks. Recipe changes now go to the feedstocks.

The one piece still proposed rather than accepted is an `lfric-env` metapackage —
this repo's `envs/lfric-env.yaml` plus `scripts/lfric-env-activate.sh`, as a
package. Until (unless) that lands, this repo is the way to get the environment.

## Licence

The packaging in this repo is BSD-3-Clause (see [`LICENSE`](LICENSE)), matching
conda-forge feedstock convention. Each *packaged* project keeps its own upstream
licence, recorded in its feedstock's recipe.
