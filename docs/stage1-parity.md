# Stage-1 parity: is the conda environment the same as the Spack one?

Stage 1 is a **contract**, not an implementation: it must put a user in a state
where any Stage-2 activity works, and Stage 2 must not be able to tell which
mechanism got them there. This document audits that claim against
[ickc/lfric-env-isambard][spack-repo], one line at a time.

[spack-repo]: https://github.com/ickc/lfric-env-isambard

**Verdict: yes, with three intended differences** — the Cray/Slingshot MPI stack has
no conda analogue (by design: the conda environment corresponds to the Spack repo's
portable `spack` variant, not its `cray` variant), `foxml` is dropped as
vestigial, and the compiler is gcc 15.3 rather than 14.3 because that is the
generation conda-forge's Fortran packages are built with. Everything else matches, and three of the Spack side's workarounds turn
out to be unnecessary here.

The claim is not left as an argument: both Stage-2 examples run against this
environment in CI on `linux-64` and `linux-aarch64` — including a real Rose/Cylc
science suite, end to end. See [`.github/workflows/stage2.yml`](../.github/workflows/stage2.yml).

## What Stage 1 has to deliver

Two things, and they are the two halves of this audit:

1. **Contents** — the packages. On the Spack side that is the direct dependency
   list of the `lfric-apps-isambard` bundle; here it is
   [`envs/lfric-env.yaml`](../envs/lfric-env.yaml).
2. **Activation** — what changes in your shell. On the Spack side that is
   `scripts/lfric-env.lua` (via `module load`); here it is
   [`scripts/lfric-env-activate.sh`](../scripts/lfric-env-activate.sh) (via
   `conda activate`).

## 1. Contents

Every direct dependency of the Spack bundle, and its conda counterpart. Versions
are the ones each mechanism actually resolved (Spack: the `2026.07.21` build's
`spack.lock`; conda: a September 2026 solve of `envs/lfric-env.yaml` on
`linux-aarch64`, every package from conda-forge).

| Spack bundle spec | Spack got | conda spec | conda got | note |
|---|---|---|---|---|
| `mpi` (provider) | `cray-mpich@9.1.0` / `mpich@5.0.1` | `mpich` | `mpich 5.0.1` | **a real difference** — see below |
| `hdf5+fortran+mpi` | `1.14.3` | `hdf5 * mpi_mpich_*` | `2.2.0` | newer; conda-forge only ships current |
| `netcdf-c+mpi~dap` | `4.9.2` | `libnetcdf * mpi_mpich_*` | `4.10.0` | " |
| `netcdf-fortran` | `4.6.1` | `netcdf-fortran * mpi_mpich_*` | `4.6.4` | " |
| `yaxt` | `0.11.3` | `yaxt * mpi_mpich_idxtype_long_*` | `0.12.1` | the `--with-idxtype=long` build LFRic needs, selected by build string |
| `xios@2701` | `2701` | `xios 2.2701 mpi_mpich_*` | `2.2701` | conda-forge feedstock started here |
| `pfunit+mpi` | `4.19.0` | `pfunit * mpi_mpich_*` | `4.20.1` | conda-forge feedstock started here (+ `gftl`, `gftl-shared`, `fargparse`) |
| `shumlib` | `2026.07.2` | `shumlib` | `2026.07.2` | conda-forge feedstock started here |
| `blitz` | `1.0.2` | `blitzpp` | `1.0.2` | conda-forge feedstock started here; the name `blitz` is taken |
| `foxml` | `6f60cf1` | *(none)* | — | **dropped** — see below |
| `gmake` | `4.4.1` | `make` | `4.4.1` | |
| `pkgconf` | `2.5.1` | `pkg-config` | `0.29.2` | same role; either satisfies LFRic's `pkg-config` calls |
| `python@3.12+shared` | `3.12.13` | `python 3.12.*` | `3.12.14` | |
| `py-setuptools@:79` | `79.0.1` | *(unpinned)* | `84.x` | pin is a Spack-build workaround; see below |
| `py-fparser` | `0.2.4` | `fparser` | `0.2.4` | |
| `py-psyclone@3.3.1` | `3.3.1` | `psyclone 3.3.1` | `3.3.1` | the version LFRic vn3.2 requires |
| `py-jinja2` | `3.0.3` | `jinja2` | `3.0.3` | |
| `py-pyyaml` | `6.0.3` | `pyyaml` | `6.0.3` | |
| `py-rose-picker` | `2026.03.2` | `rose-picker` | `2026.07.1` | conda-forge feedstock started here; newer |
| `py-metomi-rose` | `2.4.2` | `metomi-rose` | `2.7.1` | newer |
| `py-cylc-flow` | `8.4.2` | `cylc-flow` | `8.6.6` | newer |
| `py-cylc-rose` | `1.5.1` | `cylc-rose` | `1.7.2` | newer |
| `py-ansimarkup` | `2.1.0` | `ansimarkup` | `2.1.0` | |
| `py-colorama` | `0.4.6` | `colorama` | `0.4.6` | |
| *(compiler)* `gcc@14.3.0` | system external | `gcc`/`gxx`/`gfortran 15.3.*` | `15.3.0` | **different generation, forced** — see below |
| *(none)* | — | `sci-fab` | `2.2.0` | extra: LFRic's newer Fab build system |
| *(none)* | — | `cmake` | `4.4.3` | extra: convenience for building against the env |

### The compiler: load-bearing, and the one difference forced on us

gfortran can only read `.mod` files written by its own module-format generation, so
every Fortran package in an environment, and the compiler the user builds LFRic
with, have to agree. The Spack build gets that by declaring the system
`/usr/bin/gcc-14` as an external and pinning `c`/`cxx`/`fortran` to it.

The conda environment cannot choose freely, because it consumes Fortran modules it
did not build: conda-forge builds its Fortran stack (`mpich`'s `mpi.mod`,
`netcdf-fortran`, `yaxt`, `xios`, `shumlib`, ...) with its global
`fortran_compiler_version`, which is **15** as of September 2026. gfortran 15 writes
module format version 16, which gfortran 14.3 rejects (`Cannot read module file
... because it was created by a different version of GNU Fortran`). So the
environment pins **gcc 15.3**, and will move again whenever conda-forge's pinning
does. LFRic vn3.2 compiles with it, and the u-dr932 suite runs on it: see the
checks below.

The environment still ships its own toolchain, which remains the stronger position:
it does not depend on the host having one. `scripts/test-env.sh` checks the module
agreement directly by compiling `use xios` + `use yaxt` with the environment's own
`mpif90` (`MODULES_OK`).

### MPI: the other real difference

The Spack repo has two variants. `cray` uses the system `cray-mpich` over
Slingshot (`cxi`), which is the only way to get RDMA and multi-node scaling on
Isambard 3; `spack` builds `mpich` from source and is the portable, single-node
fallback. **The conda environment is the analogue of the `spack` variant**: same
`mpich 5.0.1`, same from-source HDF5/netCDF story.

There is no conda analogue of the `cray` variant and there should not be — a Cray
PE stack is a property of the machine, not of a package manager. On a Cray EX,
either use the Spack `cray` variant, or expect the conda environment to behave like
the `spack` one (single node, TCP). Everything above the MPI layer is unchanged.

### foxml: dropped, deliberately

`foxml` (the [andreww/fox][fox] Fortran/XML library) is in the Spack bundle but
**nothing in LFRic references it**: no `-lFoX`, no `use fox_*`, no mention in any
`.mk` or `Makefile` across `lfric_core` and `lfric_apps` at `2026.07.1`. It is a
leftover from the Met Office `simit-spack` lineage the bundle was ported from. It
is not packaged here, and its absence is not a functional gap. (Should a future
LFRic release start using FoX, it is an easy recipe — CMake, C + Fortran only.)

[fox]: https://github.com/andreww/fox

### py-setuptools@:79: a Spack-only workaround

Spack builds Python packages from source, so the setuptools that does the building
is part of the environment and its version matters. conda-forge ships built
packages, so setuptools is a runtime library like any other and the pin has nothing
to constrain. Left unpinned here; the environment resolves `setuptools 83.x` and
every build in CI passes with it.

## 2. Activation

What the two mechanisms export. Left column is `scripts/lfric-env.lua` (Spack,
`spack` variant); right is `conda activate` + `scripts/lfric-env-activate.sh`.

| what | Spack modulefile | here | same effect? |
|---|---|---|---|
| `FC`, `LDMPI` | view's `mpif90` | `mpif90` | ✅ identical, and for the same reason: LFRic picks its flag file by the compiler's **leaf name** (`fortran/mpif90.mk`) |
| `CXX` | view's `mpic++` | `mpic++` | ✅ same — `cxx/mpic++.mk` exists, `mpicxx.mk` does not |
| C++ backend detection | — (the view's `mpic++` already reports `g++`) | `MPICH_CXX=$GXX` | ⚠️ **extra here**: conda's `mpic++` wraps the `c++`-named driver, whose `--version` does not contain "g++", which `cxx/mpic++.mk` requires. Points the wrapper at the identically-configured `g++`-named driver (same gcc, ABI-safe) |
| `FPP` | `cpp -traditional-cpp` | same | ✅ |
| `LFRIC_TARGET_PLATFORM` | `meto-spice` | same | ✅ |
| `FFLAGS` | `-I<view>/include`, prepended | `-I$CONDA_PREFIX/include`, prepended | ✅ |
| `LDFLAGS` | `-L<view>/lib{,64}` + `-rpath` | `-L$CONDA_PREFIX/lib` + `-rpath` | ✅ (conda has no `lib64` split) |
| `SHUMLIB_ROOT` | shumlib's own prefix | `$CONDA_PREFIX` | ✅ (conda merges prefixes, so it is the env root) |
| `PATH` | view's `bin` prepended | `conda activate` does it | ✅ |
| `LD_LIBRARY_PATH`, `LIBRARY_PATH` | view's `lib`, `lib64` prepended | *(not needed)* | ✅ conda packages carry `RPATH`/`$ORIGIN`, and the compiler activation already sets the search paths |
| `PYTHONPATH` + `CYLC_PYTHONPATH` + `ROSE_PYTHONPATH` | all three set to the view's site-packages | *(not needed)* | ✅ **simpler here** — see below |
| `PSYCLONE_CONFIG` | set (Spack launcher's shebang python cannot find it) | *(not needed)* | ✅ conda's `psyclone` finds its own config |
| `APPS_ROOT_DIR`, `CORE_ROOT_DIR` | the repo's vendored trees | the repo's staged `vendor/` | ✅ same role; a suite overrides both |
| `HDF5_USE_FILE_LOCKING=FALSE` | in the suite activator | in the contract | ✅ same value, one level up |
| `SPACK_ENV`, Cray PE `module load`s | set / loaded | — | n/a: mechanism-specific by definition |

### The PYTHONPATH triple that conda does not need

The Spack modulefile has to put the view's `site-packages` on `PYTHONPATH`, because
Spack's console scripts shebang a base python whose `sys.path` does not include the
environment. But **cylc and rose both strip every `PYTHONPATH` entry from
`sys.path` at start-up** (cylc-flow #5124), which breaks them — so the modulefile
also mirrors the same paths into `CYLC_PYTHONPATH` and `ROSE_PYTHONPATH`, which
each tool re-adds before stripping. Three variables to work around one layout.

A conda environment has a single coherent `python` with its own `site-packages`, so
none of it is needed: `cylc`, `rose` and `psyclone` are ordinary entry points of the
environment's own interpreter. This is a place where the conda mechanism is simply
better, and it is visible in the activation contract being ~40 lines of exports
rather than a modulefile with an escape hatch for Lmod's static `load()` scan.

## 3. What is NOT part of Stage 1 either way

Worth stating, because it is a common confusion: **the LFRic source is not Stage
1.** Both repos pin the same six MetOffice repos at the same refs (`2026.07.1`) and
apply the same patch stack — as git submodules there, as
[`sources.yaml`](../sources.yaml) + `scripts/stage-sources.sh` here — precisely so
that a Stage-2 comparison isolates the environment. See
[`patches/README.md`](../patches/README.md).

## 4. How this is kept honest

| check | where | what it proves |
|---|---|---|
| package builds, 4 platforms | the conda-forge feedstocks | every package exists where LFRic runs |
| `scripts/test-env.sh` | local / on Isambard 3 | `use mpi`, `use netcdf`, `use xios`, `use yaxt` compile with the env's own gfortran |
| `cylc validate` on every suite | `build.yml` lint job | the ported suites parse and validate |
| **minimal-compile** | `stage2.yml` | the science target `lfric_atm` compiles and links against the env |
| **science-suite (u-dr932)** | `stage2.yml` | rose+cylc drive the whole thing and the model **runs**: extract → build → mesh → 6-rank forecast |
| minimal-compile + u-dr932 at full size | `examples/*/*.sbatch` on Isambard 3 | the same, on the production machine: C48_MG, 24 ranks, 72 timesteps (1 day) |
