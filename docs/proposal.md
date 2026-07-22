# Porting Stage 1 (the LFRic environment) from Spack to conda

Survey + proposal. Derived from `lfric-env-isambard` @ `b59d35e`, the concretized
`spack.lock` (193 specs, both variants), `mo-spack-packages`, and live conda-forge
queries (2026-07-22, `linux-aarch64`).

---

## 1. What Stage 1 actually is

The Spack lock has 193 nodes, but that is Spack building its own world (perl, rust,
cmake, glib, graphviz, …). Semantically the environment is ~25 things:

| group | contents |
|---|---|
| **(a) toolchain** | `gcc@14.3.0` C/C++/Fortran (system external, `/usr/bin/gcc-14`) |
| **(b) MPI + parallel I/O** | `cray-mpich@9.1.0` \| `mpich`; `hdf5@1.14.3 +mpi+fortran+hl`; `netcdf-c@4.9.2 +mpi~dap`; `netcdf-fortran@4.6.1` |
| **(c) LFRic numerical / IO libs** | `xios@2.2701`, `yaxt@0.11.3`, `shumlib@2026.07.1`, `pfunit@4.19` (+`gftl`, `gftl-shared`, `fargparse`), `blitz` (Blitz++ — XIOS only), `foxml` |
| **(d) build + workflow python** | `python@3.12`, `py-psyclone@3.3.1`, `py-fparser`, `py-rose-picker@2026.03.2`, `py-jinja2`, `py-pyyaml`, `py-sympy`; `py-metomi-rose`, `py-cylc-flow`, `py-cylc-rose`, `py-metomi-isodatetime`, `py-ansimarkup`, `py-colorama` |
| **(e) the exported contract** | `scripts/lfric-env.lua`: `FC`/`LDMPI`/`CXX`, `FFLAGS`/`LDFLAGS`, `LIBRARY_PATH`/`LD_LIBRARY_PATH`, `PATH`, `SHUMLIB_ROOT`, `PSYCLONE_CONFIG`, `PYTHONPATH`+`CYLC_PYTHONPATH`+`ROSE_PYTHONPATH` |

**What LFRic actually links** (`lfric_core/infrastructure/build/import.mk`,
`components/lfric-xios/build/import.mk`, `tests.mk`):

```
-lxios -lnetcdff -lnetcdf -lyaxt -lyaxt_c -lstdc++      # applications
-lpfunit -lfunit -lfargparse -lgftl-shared-v2           # unit tests only
$SHUMLIB_ROOT                                            # lfric_apps (UM physics)
```

**Finding: `foxml` is dead weight.** Nothing in `lfric_core` or `lfric_apps`
`use`s FoX or links it — no `EXTERNAL_*_LIBRARIES` entry, no `use fox_*`. It is
vestigial in the bundle. Drop it from the conda port. (Convenient, because
conda-forge's `fox` — correctly the `andreww/fox` Fortran library — was last built
on aarch64 in 2023 against gfortran 11.3, so its `.mod` files would be unusable
anyway.)

---

## 2. conda-forge coverage — the gap is 8 recipes, only 1 of them hard

### Already there (nothing to do)

| need | conda-forge | note |
|---|---|---|
| gcc/g++/gfortran 14.3 | `gcc_linux-aarch64` / `gxx_` / `gfortran_` **14.3.0** | exact version match available |
| mpich | `mpich` 5.0.1 (aarch64) | plus `openmpi` |
| **system MPI (cray)** | `mpich=4.3.2=external_*` **on linux-aarch64** | the direct analogue of the `cray` variant |
| hdf5 +mpi+fortran | `hdf5` 2.1.0 `mpi_mpich_*` | older 1.14.x builds also available |
| netcdf-c +mpi | `libnetcdf` 4.9.3 / 4.10.x `mpi_mpich_*` | feedstock is `libnetcdf`, not `netcdf-c` |
| netcdf-fortran | `netcdf-fortran` 4.6.3 `mpi_mpich_*` | built vs **gfortran 14.3** |
| PSyclone | `psyclone` **3.3.1** noarch | *exactly* the version the bundle pins |
| fparser | `fparser` 0.2.4 noarch | newer than spack's 0.2.2 |
| FAB build system | `sci-fab` **2.2.0** noarch | `lfric_core/lfric_build` is moving to FAB |
| rose | `metomi-rose` 2.7.1 | spack has 2.4.2 |
| cylc | `cylc-flow` 8.6.5, `cylc-rose` 1.7.2, `metomi-isodatetime` | spack has 8.4.2 / 1.5.1 |
| jinja2, pyyaml, sympy, ansimarkup, colorama, psutil, pyzmq, graphene, urwid, sqlalchemy, cmake, make, pkg-config, graphviz, python | all ✅ aarch64/noarch | |

### The gap

| package | status | effort | notes |
|---|---|---|---|
| **xios** `2.2701` | absent everywhere | **hard** | FCM/`make_xios` build; needs an `arch-CONDA.{env,path,fcm}` triplet. Port from `spack-repo/lfric-isambard/packages/xios` incl. `gcc_remap_standard_headers.patch`. Consider also packaging `3.0.4.0`. |
| **blitzpp** (Blitz++) | absent | easy | CMake. ⚠️ the name `blitz` on conda-forge is **Blitz.js** (noarch JS) — must use `blitzpp`. XIOS-only dep. |
| **rose-picker** | absent | trivial | `MetOffice/rose_picker`, plain setuptools → `noarch: python`. |
| **yaxt** | **exists, `linux-64`/`osx-64` only** | easy | Existing feedstock already has `mpi_mpich_*` / `mpi_openmpi_*` variants at 0.11.5.1. Just needs `linux-aarch64` added — a migration PR, no new recipe. |
| **shumlib** | absent from conda-forge; **ACCESS-NRI ships `shumlib` 2026.07.2** (linux-64) | easy | CMake, tagged tarballs + sha256 in the MO spack recipe. Reuse/adapt ACCESS-NRI's recipe; they are a plausible co-maintainer. |
| **pfunit** | absent | medium | CMake; test-only. Deferred past MVP. |
| **gftl**, **gftl-shared**, **fargparse** | absent | easy | NASA/GMAO CMake libs; pfunit deps. |
| *(vernier)* | absent | — | MO profiler; not in the current bundle. Later, if ever. |

No prior art for xios/pfunit/gftl/rose-picker on any anaconda.org channel
(`dubos/xios` is an unrelated one-off). shumlib is the only package anyone else
has already done.

---

## 3. The good news you should design around

1. **conda-forge's aarch64 Fortran stack is currently built with gfortran 14.3.0**
   (`netcdf-fortran` → `libgfortran5 >=14.3.0`, `libgcc >=14`). That is the *same*
   compiler this repo pins. So the `.mod` compatibility story this repo already
   verified — gcc 14.3 reads Cray's GFORTRAN module-format v15 `mpi.mod` — carries
   over unchanged. Pin `gfortran_linux-aarch64=14.3.*` and the Cray variant stays
   on the ground that Spack already proved.

2. **The two variants map over, and the cray one gets *simpler*.** Spack's `cray`
   variant externalizes cray-mpich *and* Cray HDF5 *and* Cray netCDF, which is why
   `spack-env/cray/spack.yaml` is full of `LIBRARY_PATH` surgery. In conda the
   equivalent is **system MPI only**: `mpich=*=external_*` + `module load cray-mpich`;
   HDF5/netCDF come from conda-forge built against the MPICH ABI. Less coupling,
   fewer version-lockstep gotchas ("bump one, bump all three" disappears).

3. **The cylc/rose `PYTHONPATH` hack disappears.** `lfric-env.lua` has ~15 lines
   mirroring the view's site-packages into `CYLC_PYTHONPATH`/`ROSE_PYTHONPATH`
   because cylc/rose strip `PYTHONPATH` on entry. In conda they are installed
   *into* the env's `site-packages`, so nothing needs `PYTHONPATH` at all.

4. **`conda activate` ≈ `module load` is a real 1:1.** conda's activation scripts
   are the direct analogue of the Lmod modulefile. The `lfric-env` metapackage
   carries an `activate.d/` script that exports the same contract
   (`FC`/`LDMPI`/`CXX`/`SHUMLIB_ROOT`/`PSYCLONE_CONFIG`/…). Stage 2 then genuinely
   does not care which produced it.

---

## 4. Risks to design against

1. **XIOS is the whole critical path.** Everything else is a weekend. Budget
   accordingly; do it last so the rest is already de-risked, or first if you want
   to know early whether the project is viable.
2. **`FC` leaf-name dispatch.** LFRic picks its flag file by the *leaf name* of
   `$FC` (`infrastructure/build/fortran/<fc>.mk` — `gfortran.mk`, `mpif90.mk`,
   `crayftn.mk`…). conda's compiler activation sets
   `FC=aarch64-conda-linux-gnu-gfortran`, for which there is no `.mk`. The
   `lfric-env` activation script must override to `FC=mpif90`, `LDMPI=mpif90`,
   `CXX=mpic++` — exactly what `lfric-env.lua` does for the spack variant today.
3. **Version drift vs what LFRic 2026.07.1 was validated against.** conda-forge is
   *ahead*: hdf5 2.1.0 vs 1.14.3, libnetcdf 4.10.x vs 4.9.2, rose 2.7.1 vs 2.4.2,
   cylc 8.6.5 vs 8.4.2. Newer is usually fine but is not free; pin deliberately in
   the env spec and be ready to select older builds.
4. **Tracking conda-forge's global compiler pin.** Today aarch64 is on gfortran
   14.3; when conda-forge migrates to 15, every Fortran `.mod` in the stack moves
   with it and the Cray `mpi.mod` compatibility must be re-verified.
5. **conda-forge staleness for niche Fortran packages** — `fox` (2023, gfortran
   11.3) is the cautionary example. Any Fortran dep must be *currently* migrated,
   not merely present.
6. **`blitz` name collision** — Blitz.js holds it. `blitzpp` (or `blitz-cpp`).

---

## 4b. VERIFIED on Isambard 3 (2026-07-22)

The MVP-1 base — every dependency conda-forge already has — was solved *and built*
on the login node (`envs/lfric-env-mvp1.yaml`, 261 packages, 312 MB):

```
gcc/gxx/gfortran_linux-aarch64  14.3.0        <- same compiler the Spack env pins
mpich 5.0.1 | hdf5 2.1.0 mpi_mpich_* | libnetcdf 4.10.0 mpi_mpich_*
netcdf-fortran 4.6.3 mpi_mpich_*
psyclone 3.3.1 | fparser 0.2.4 | sci-fab 2.2.0 | sympy 1.13.3 | jinja2 3.0.3
metomi-rose 2.7.1 | cylc-flow 8.6.5 | cylc-rose 1.7.2
```

`conda activate` alone puts `mpif90`, `mpic++`, `psyclone`, `rose`, `cylc`, `fab`
on `PATH`. A program doing `use mpi` + `use netcdf` **compiled and ran on 2 ranks**:

```
GNU Fortran (conda-forge gcc 14.3.0-19) 14.3.0
COMPILE_OK
 MPI ranks      :            2
 netCDF version : 4.10.0 of Apr 20 2026 11:56:01
```

Two things this settles:

- **The Fortran `.mod` ABI question is closed for the pure-conda variant.**
  conda-forge's `netcdf-fortran` on aarch64 is built with gfortran 14.3, and a
  14.3 compiler reads its modules. Risk #2/#4 below is real but not blocking today.
- **Risk #2 (`FC` leaf-name) is confirmed, exactly as predicted.** conda's
  activation sets `FC=aarch64-conda-linux-gnu-gfortran`; LFRic would look for a
  non-existent `build/fortran/aarch64-conda-linux-gnu-gfortran.mk`. The `lfric-env`
  metapackage's `activate.d/` **must** override `FC`/`LDMPI`/`CXX` to
  `mpif90`/`mpif90`/`mpic++`.

(Cosmetic: conda `mpich` is UCX-backed and emits RoCE warnings on the login node —
the same "portable fallback, not for production runs" caveat the `spack` variant
already carries in this repo.)

---

## 5. Proposed shape

### MVP (MVP-1): lfric_core, pure-conda MPI, linux-aarch64

Target: build and run `lfric_core/applications/simple_diffusion` (or `skeleton`)
from a `conda activate`d environment, no Spack, no Lmod.

Needs only **3 new recipes + 1 migration PR**:

- `xios` (2.2701)
- `blitzpp`
- `rose-picker`
- `yaxt` → add `linux-aarch64` to the existing conda-forge feedstock

Deferred to MVP-2 (`lfric_atm` / the apps tier): `shumlib`, `pfunit` + `gftl`,
`gftl-shared`, `fargparse`.
Deferred to MVP-3: the **cray** (system-MPI) variant on Isambard 3.

### Repo layout

One repo to start. Create an org only if/when the feedstocks split out.

```
lfric-conda/
  recipes/
    xios/recipe.yaml            # rattler-build v1 format
    blitzpp/recipe.yaml
    rose-picker/recipe.yaml
    shumlib/  pfunit/  gftl/  gftl-shared/  fargparse/
  variants/
    conda_build_config.yaml     # mpi × {mpich, openmpi, external}, gfortran pin
  envs/
    lfric-env-mpich.yaml        # the deliverable (portable / pure conda)
    lfric-env-cray.yaml         # system-MPI variant for Isambard 3
    lfric-env.recipe.yaml       # the `lfric-env` metapackage + activate.d/
  scripts/
    build-all.sh  test-env.sh   # no-tooling-required entry points
  pixi.toml                     # 1:1 wrappers, same convention as this repo
  .github/workflows/            # rattler-build → channel
```

### Tooling

- **rattler-build** with the v1 `recipe.yaml` format — conda-forge accepts it, so
  recipes go upstream *unchanged* rather than being rewritten.
- **prefix.dev** as the interim public channel (free, designed for exactly this),
  or an anaconda.org org channel if you prefer the incumbent.
- **pixi** for the dev loop and for end-user install, keeping this repo's
  "every pixi task is a thin wrapper around a script" rule.

### Upstreaming order (easiest first, so the process is learned on cheap PRs)

1. `rose-picker` → conda-forge/staged-recipes (trivial noarch python)
2. `yaxt` → linux-aarch64 migration PR on the existing feedstock
3. `blitzpp`
4. `gftl`, `gftl-shared`, `fargparse`, `pfunit`
5. `shumlib` (approach ACCESS-NRI first — they already maintain a recipe)
6. `xios` (last; hardest; may warrant staying in-house longest)

Local channel throughout, so nothing is blocked on staged-recipes review latency.

### Acceptance test — reuse this repo

The success criterion for the conda port is precisely:

> `examples/minimal-compile/build.sh` (and later the `u-*` science suites) pass
> unchanged, with the environment supplied by `conda activate` instead of
> `module load lfric-env/<version>/<variant>`.

That is the cleanest possible proof of "Stage 2 doesn't care", and it costs
nothing to set up because the tests already exist here.
