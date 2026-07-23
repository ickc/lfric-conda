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
| `yaxt` | ✅ packaged — built `--with-idxtype=long` (64-bit `Xt_int`, required by LFRic); upstream feedstock also needs a `linux-aarch64` build |
| `shumlib` | ✅ packaged (apps tier — `lfric_apps` links `-lshum`) |
| `gftl`, `gftl-shared`, `fargparse`, `pfunit` | ✅ packaged (unit-test tier; versioned-subdir CMake installs) |

**All nine build green in CI on `linux-64` and `linux-aarch64`.** macOS
(`osx-arm64` + `osx-64`) is being brought up now — see
[`docs/platform-coverage.md`](docs/platform-coverage.md) for the per-package
support policy, the clang-vs-GNU decision, and why Windows is out of scope.
Nothing has been upstreamed to conda-forge yet — see [Upstreaming](#upstreaming).

**Stage 2 works:** the apps-tier science target `lfric_atm` compiles and links
entirely against the conda environment — see
[`examples/minimal-compile/`](examples/minimal-compile/build.sh).

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

## Compiling LFRic (Stage 2)

[`examples/minimal-compile/build.sh`](examples/minimal-compile/build.sh) compiles
the apps-tier science target `lfric_atm` against
[`envs/lfric-env-mvp2.yaml`](envs/lfric-env-mvp2.yaml) (MVP-1 + `shumlib`) — the
conda analogue of the same example in the Spack repo, and the proof that an end
user can `conda activate` and build LFRic with no Spack or Lmod:

```console
$ micromamba create -n lfric-conda-stage2 -f envs/lfric-env-mvp2.yaml \
    -c ./local-channel -c conda-forge
$ micromamba run -n lfric-conda-stage2 bash examples/minimal-compile/build.sh
...
LFRIC_ATM_OK
```

It reuses the LFRic *source* vendored in the sibling Spack repo (identical source;
only the environment differs) and produces a ~98 MB `lfric_atm` binary linking the
env's `yaxt`/`netcdf`/`mpich`/`hdf5`.

The script also codifies the **`lfric-env` activation contract** — what the future
`lfric-env` metapackage's `activate.d/` must export, the conda analogue of the
Spack repo's `scripts/lfric-env.lua`. Two of these are non-obvious and were only
found by compiling:

- **`FC=mpif90 CXX=mpic++`** — LFRic dispatches its compiler flag files by the
  *leaf name* of the compiler (`fortran/mpif90.mk`, `cxx/mpic++.mk`), so conda's
  `aarch64-conda-linux-gnu-*` names do not work.
- **`MPICH_CXX=<host>-g++`** — `cxx/mpic++.mk` identifies the C++ backend from the
  first word of `mpic++ --version` and requires it to contain `g++`. conda's
  `mpic++` wraps the `c++`-named driver, so point it at the identically-configured
  `g++`-named one (same gcc, ABI-safe). `FC` needs no equivalent because
  `gfortran --version` always prints "GNU Fortran".

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
