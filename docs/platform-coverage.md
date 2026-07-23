# Platform coverage

Which operating systems and architectures these packages are built for, why, and
how it is wired. Companion to [`proposal.md`](proposal.md) (what Stage 1 contains)
and the repo [`README.md`](../README.md) (per-package status).

## Summary

| target | tier | who | status |
|---|---|---|---|
| `linux-64` | **production** | build farms, CI | supported |
| `linux-aarch64` | **production** | Isambard 3 (Cray EX / Grace) | supported |
| `osx-arm64` | **developer** | Apple-Silicon laptops | being brought up (this change) |
| `osx-64` | developer (best-effort) | Intel Macs (declining) | being brought up (this change) |
| `win-64` | — | — | **out of scope** (see below) |

Linux is and stays the production target — every real LFRic run is on Isambard 3.
macOS is a **developer-convenience** tier: letting someone build and hack on the
LFRic pieces on a Mac. It is worth doing anyway because **conda-forge upstreaming
requires each feedstock to build wherever its source does**, so the work is not
wasted even for packages no one will run a model with on a laptop.

There are two distinct goals, and they have different platform reach:

- **Per-package conda-forge citizenship** — each recipe builds wherever its
  *source* supports. This reaches macOS cleanly for most of the set.
- **The full LFRic environment + a Stage-2 compile** — bounded by the *weakest*
  link in the chain (XIOS, and the toolchain). Feasible on `osx-arm64` for a
  developer; never on Windows.

## The two hard constraints

Everything below follows from these two facts, both verified against conda-forge's
live repodata and its global pinning (see [Appendix](#appendix-verified-facts)).

### 1. MPI

`mpich`/`openmpi` are built for `linux-64`, `linux-aarch64`, `osx-64`, and
`osx-arm64` — **but not Windows**. Windows conda-forge has only `msmpi` and Intel
`impi_rt`, which are different APIs with no `mpicc`/`mpif90` story our recipes can
use. Three packages hard-depend on `${{ mpi }}` (`yaxt`, `xios`, `pfunit`), so
those cannot exist on Windows at all.

### 2. Toolchain and the Fortran `.mod` ABI

The stack is pinned to **gfortran 14** because Fortran `.mod` files are only
readable by the compiler generation that wrote them, so every consumer must use
the same generation conda-forge built `netcdf-fortran`/`hdf5` with. conda-forge
pins `fortran_compiler_version: 14` on **both linux and osx**, so the `.mod` ABI
lines up on macOS exactly as on linux.

C/C++ is where the platforms differ. conda-forge's osx toolchain is **mixed by
family**: **clang/clang++ for C/C++ (LLVM, libc++), gfortran for Fortran (GCC)**.
On linux it is uniformly GNU (gcc/g++/gfortran). So the linux-shaped pins —
`c_stdlib: sysroot` (glibc) and `c_compiler_version/cxx_compiler_version: 14`
(gcc) — are wrong on macOS, where the C-stdlib is the macOS *deployment target*
and C/C++ is clang. This is handled by [per-OS variant overlays](#variant-config).

## Per-package support policy

| package | MPI | Fortran `.mod` | macOS upstream policy (evidence) | `osx-arm64` / `osx-64` | `win-64` |
|---|:--:|:--:|---|:--:|:--:|
| `rose-picker` | – | – | `noarch: python` — every platform already | ✅ (noarch) | ✅ (noarch) |
| `blitzpp` | – | – | portable C++ templates; Spack builds it broadly | ✅ expected | ⚠️ possible, no consumer |
| `gftl` | – | ✓ | NASA Goddard; officially Linux + macOS | ✅ expected | ✗ |
| `gftl-shared` | – | ✓ | ″ | ✅ expected | ✗ |
| `fargparse` | – | ✓ | ″ | ✅ expected | ✗ |
| `pfunit` | ✓ | ✓ | README: *"ported to Linux and Apple OS X"*, gfortran 12+ | ✅ expected | ✗ (no mpich) |
| `yaxt` | ✓ | ✓ | conda-forge feedstock **already builds `osx-64`** | ✅ expected | ✗ (no mpich) |
| `xios` | ✓ | ✓ | ships a **`GCC_MACOSX`** arch; "builds with clang+gfortran on OSX" | 🟡 needs an osx arch triplet | ✗ (no mpich) |
| `shumlib` | – | ✓ | **unknown** — CMake (portable) but ACCESS-NRI ship `linux-64` only | 🟡 probe via CI | ✗ |

"expected" = source is known-portable and the infrastructure (mpich,
mpi-variant hdf5/netcdf, gfortran 14, the noarch python tools) is all present on
osx; **CI is the gate that turns expected into supported.** The two 🟡 rows are the
real unknowns:

- **`xios`** — its FCM build reads hand-written `arch-*` files. Upstream ships a
  `GCC_MACOSX` arch, so macOS is a known target, but our `arch-CONDA` triplet was
  written for Linux; osx needs its own (clang C/C++ backend, `.dylib`/`-install_name`
  linker conventions).
- **`shumlib`** — no macOS precedent anywhere (even ACCESS-NRI, who maintain a
  shumlib conda recipe, ship `linux-64` only). CMake helps, but the UM C code may
  carry Linux-isms. If it does not build, it gets `skip` on osx with a recorded
  reason rather than a red check — `shumlib` is only needed by the `lfric_apps`
  tier, not `lfric_core`.

## macOS: clang vs GNU (the toolchain decision)

On macOS the C/C++ compiler can be **clang** (conda-forge's osx convention) or
**GNU gcc/g++** (conda-forge ships both for osx). They pull opposite ways:

- **clang** — what conda-forge uses on osx. Building this way keeps each recipe
  **upstreamable** (it works under conda-forge's global pinning with no
  special-casing) and **ABI-consistent** with the rest of conda-forge osx. The
  catch is C++: clang++ uses **libc++**, g++ uses **libstdc++** — incompatible C++
  ABIs. Since ~all of conda-forge osx is libc++, a g++/libstdc++ build of a
  C++-exposing package is an ABI island the ecosystem rejects.
- **GNU** — matches linux exactly and satisfies LFRic's own build system, whose
  `cxx/mpic++.mk` insists the C++ compiler identify as `g++`. But it is
  non-conventional on osx and (for C++ packages) ABI-incompatible with conda-forge.

**Decision: build the packages the conda-forge way on osx — clang C/C++ +
gfortran.** Reasons:

1. It is what we upstream. Getting these into conda-forge is the endgame
   ([README "Upstreaming"](../README.md#upstreaming)); the recipes must build
   under conda-forge's pinning as-is.
2. It is sufficient for the stated goal — *the packages build on macOS*.
3. The GNU-on-osx question only arises for **compiling LFRic itself on a Mac** (a
   Stage-2-on-macOS activity, not part of "add macOS to the packages"): there
   LFRic's `mpic++.mk` wants g++, and linking `libxios.a`'s C++ objects wants one
   consistent C++ runtime.

Crucially, choosing clang now does **not** paint us into a corner, because of the
repo's **recipe ⟂ variant separation**: the recipe is compiler-agnostic
(`${{ compiler('cxx') }}`); *which* compiler it resolves to is set by the variant
config, not the recipe. conda-forge's pinning resolves it to clang on osx (what we
upstream); if we later pursue a Stage-2 compile on a Mac, our **local** `variants/`
can resolve the *same, unchanged* recipe to `gxx` on osx — no recipe fork. So:

- We do **not** ship two compiler variants of each package (a compiler-ABI variant
  axis, unlike MPI, is not something conda-forge has or wants — it would only ever
  take the clang build, and every C++ dependent would have to pin the family
  through). We build one way (clang) and keep the GNU path available as a local
  variant override for if/when it is needed.

## Windows: out of scope

Not attempted, by design:

- **No `mpich`/`openmpi`** on Windows, so `yaxt`/`xios`/`pfunit` cannot be built;
  porting them to `msmpi`/Intel-MPI is a research project their upstreams do not
  support.
- The GNU-`.mod` toolchain is a Unix construct; Windows conda-forge Fortran is a
  different toolchain.
- **LFRic itself has no Windows build**, so the environment is unsatisfiable there
  regardless of how many individual libraries one packaged.

Only `rose-picker` (noarch) lands on Windows, incidentally. Net end-to-end payoff
of pursuing Windows: zero. If that ever changes, it is a separate effort, not a
variant tweak.

## How it is implemented

### Variant config

rattler-build does **not** honour conda-build `# [osx]` selector comments inside a
variant file, but it **does merge multiple `--variant-config` files**. So the
config is split:

- [`variants/conda_build_config.yaml`](../variants/conda_build_config.yaml) —
  common keys (`mpi`, `fortran_compiler_version: 14`).
- [`variants/linux.yaml`](../variants/linux.yaml) — glibc `sysroot` 2.28, gcc/g++ 14.
- [`variants/osx.yaml`](../variants/osx.yaml) — `macosx_deployment_target` 11.0,
  clang/clang++ 19.

[`scripts/common.sh`](../scripts/common.sh) picks the overlay by `uname` (the build
host is the native target both in CI and locally) and
[`scripts/build-recipe.sh`](../scripts/build-recipe.sh) passes base + overlay. The
union of base + `linux.yaml` is value-identical to the previous single file, so
linux builds are unchanged.

### CI

One reusable workflow, [`build-pkg.yml`](../.github/workflows/build-pkg.yml),
builds a single recipe across the four-platform matrix
(`ubuntu-latest`, `ubuntu-24.04-arm`, `macos-13`, `macos-14`). The orchestrator,
[`build.yml`](../.github/workflows/build.yml), calls it once per package and wires
the build-dependency DAG with `needs:`:

```
roots:      rose-picker  blitzpp  yaxt  shumlib  gftl
dependents: xios→blitzpp   gftl-shared→gftl   fargparse→{gftl,gftl-shared}
            pfunit→{gftl,gftl-shared,fargparse}
```

Each package uploads its built channel as `chan-<package>-<target>`; a dependent
restores its deps' channels (same run, per-dep directories so their
`repodata.json` do not collide) and points `scripts/build-recipe.sh` at them via
`LFRIC_DEP_CHANNELS`. The result is a per-(package × platform) grid of checks that
fail and re-run independently — so iterating on one package/platform does not
rebuild the ones that already pass.

## Appendix: verified facts

conda-forge global pinning ([`conda-forge-pinning-feedstock`], July 2026):

| key | linux | osx | win |
|---|---|---|---|
| `fortran_compiler_version` | 14 | **14** | 5 |
| `c_compiler_version` / `cxx_compiler_version` | 14 (gcc) | **19 (clang)** | — |
| `c_stdlib` | `sysroot` | `macosx_deployment_target` | `vs` |
| `c_stdlib_version` | 2.17¹ | **11.0** | — |

¹ we use 2.28 on linux, not conda-forge's 2.17 — required so MPI links against
conda-forge's libfabric (`getrandom@GLIBC_2.25`); see `variants/linux.yaml`.

Availability (conda-forge, confirmed via the solver / anaconda.org API):

- `mpich`, `openmpi`: `linux-64/aarch64`, `osx-64/arm64` — **not `win-64`**.
- `gcc`/`gxx`/`gfortran` **and** `clang`/`clangxx`: all of linux + osx (+ win).
  So an all-GNU osx toolchain is available if ever needed.
- `hdf5`, `libnetcdf`, `netcdf-fortran` with `mpi_mpich_*` builds: present on
  `osx-arm64` (and osx-64).
- `psyclone`, `fparser`, `sci-fab`, `metomi-rose`, `cylc-flow`, `cylc-rose`:
  `noarch` — available on every platform.
- `yaxt` already on conda-forge for `linux-64` + `osx-64` (source is mac-portable;
  `osx-arm64`/`linux-aarch64` are migration gaps, not source skips).

[`conda-forge-pinning-feedstock`]: https://github.com/conda-forge/conda-forge-pinning-feedstock/blob/main/recipe/conda_build_config.yaml
