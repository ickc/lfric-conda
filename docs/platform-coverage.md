# Platform coverage

Which operating systems and architectures the LFRic packages are built for, and
why. The packages were built in this repo while they were being upstreamed; they
now live on conda-forge feedstocks, which build all four platforms below, so the
build wiring this document used to describe is theirs now. Companion to [`proposal.md`](proposal.md) (what Stage 1 contains)
and the repo [`README.md`](../README.md) (per-package status).

## Summary

| target | tier | who | status |
|---|---|---|---|
| `linux-64` | **production** | build farms, CI | supported (conda-forge) |
| `linux-aarch64` | **production** | Isambard 3 (Cray EX / Grace) | supported (conda-forge) |
| `osx-arm64` | **developer** | Apple-Silicon laptops | **supported (conda-forge)** |
| `osx-64` | developer (best-effort) | Intel Macs (declining) | **supported (conda-forge), while Intel macOS CI lasts** |
| `win-64` | — | — | **out of scope** (see below) |

All nine packages are published for all four platforms on conda-forge. Linux is and stays the production target — every real LFRic
run is on Isambard 3. macOS is a **developer-convenience** tier: letting someone
build and hack on the LFRic pieces on a Mac. It is worth doing anyway because
**conda-forge upstreaming requires each feedstock to build wherever its source
does**, so the work is not wasted even for packages no one will run a model with
on a laptop.

There are two distinct goals, and they have different platform reach:

- **Per-package conda-forge citizenship** — each recipe builds wherever its
  *source* supports. This reaches macOS cleanly for most of the set.
- **The full LFRic environment + a Stage-2 compile** — bounded by the *weakest*
  link in the chain (XIOS, and the toolchain). Feasible on `osx-arm64` for a
  developer; never on Windows.

### Stage 2 is Linux-only, and that is a separate line

The **Stage-2 examples** — compiling `lfric_atm`, and running the `u-dr932` science
suite — run in CI on `linux-64` and `linux-aarch64` only
([`stage2.yml`](../.github/workflows/stage2.yml)). Not because the environment
fails to build on macOS (it does not — all nine packages are green there), but
because **LFRic's own build system has no macOS support**: its compiler flag files
(`fortran/*.mk`, `cxx/*.mk`) cover GNU/Intel/Cray/NVIDIA on Linux, and the physics
sources it extracts from the UM assume a Linux toolchain. That is an upstream
property of the science code, not something a packaging repo can or should paper
over. macOS therefore stays what it is: a tier where you can *build the
environment*, not one where you run a model.

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
| `blitzpp` | – | – | portable C++ templates; Spack builds it broadly | ✅ green | ⚠️ possible, no consumer |
| `gftl` | – | ✓ | NASA Goddard; officially Linux + macOS | ✅ green | ✗ |
| `gftl-shared` | – | ✓ | ″ | ✅ green | ✗ |
| `fargparse` | – | ✓ | ″ | ✅ green | ✗ |
| `pfunit` | ✓ | ✓ | README: *"ported to Linux and Apple OS X"*, gfortran 12+ | ✅ green | ✗ (no mpich) |
| `yaxt` | ✓ | ✓ | conda-forge feedstock **already builds `osx-64`** | ✅ green | ✗ (no mpich) |
| `xios` | ✓ | ✓ | ships a **`GCC_MACOSX`** arch; "builds with clang+gfortran on OSX" | ✅ green (needed `-lc++`) | ✗ (no mpich) |
| `shumlib` | – | ✓ | CMake build; no prior macOS precedent, but portable in practice | ✅ green | ✗ |

All nine build green on osx-64 and osx-arm64. The infrastructure they need
(mpich, mpi-variant hdf5/netcdf, gfortran, the noarch python tools) is all
present on osx, and the two rows that looked like real risks resolved cleanly:

- **`xios`** — its FCM build reads a hand-written `arch-*` triplet. The only osx
  change needed was the C++ runtime: the Linux arch links `-lstdc++`, but the osx
  clang toolchain's C++ runtime is libc++ (`-lc++`). `build.sh` now picks the
  right one by `target_platform`; everything else (`.dylib` output, the MPI
  wrappers, the `xios_server.exe`/`libxios.a` names) worked unchanged. This is the
  concrete payoff of the clang-on-osx decision — a C++-heavy package built with
  clang, ABI-consistent with conda-forge osx.
- **`shumlib`** — despite no macOS precedent anywhere (even ACCESS-NRI, who
  maintain a shumlib conda recipe, ship `linux-64` only), its CMake build was
  portable as-is; only the test's hardcoded `libshum.so` path needed a `.dylib`
  branch. Its `.mod` ABI check passed under osx gfortran 14, confirming the
  Fortran-`.mod` premise holds on macOS.

One further osx-only fix, in `yaxt`: `libgomp` is a linux-only conda-forge
package, so the OpenMP runtime is selected per-platform (`libgomp` on linux,
`llvm-openmp` on osx), matching the upstream yaxt-feedstock.

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
upstream); if we later pursue a Stage-2 compile on a Mac, a local variant config
can resolve the *same, unchanged* feedstock recipe to `gxx` on osx — no recipe
fork. So:

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

On the conda-forge feedstocks: each one enables `linux_aarch64` and `osx_arm64`
through `provider:` in its `conda-forge.yml` (native GitHub Actions arm runners
and Azure Apple-Silicon agents respectively), and builds against conda-forge's
global pinning. The clang-on-osx decision above is simply what that pinning does,
which is why no per-OS variant overlay is needed any more.

The Stage-2 examples run in this repo's CI
([`stage2.yml`](../.github/workflows/stage2.yml)) on `linux-64` and
`linux-aarch64`, against an environment solved straight from conda-forge.

## Appendix: verified facts

conda-forge global pinning ([`conda-forge-pinning-feedstock`], September 2026):

| key | linux | osx | win |
|---|---|---|---|
| `fortran_compiler_version` | 15 | **15** | 5 |
| `c_compiler_version` / `cxx_compiler_version` | 15 (gcc) | **21 (clang)** | — |
| `c_stdlib` | `sysroot` | `macosx_deployment_target` | `vs` |
| `c_stdlib_version` | 2.17¹ | **11.0** | — |

¹ conda-forge's libfabric (pulled in by mpich) references `getrandom@GLIBC_2.25`.
The in-repo builds raised the sysroot to 2.28 for it; the xios feedstock instead
keeps the 2.17 baseline and defers that one check to runtime
(`-Wl,--allow-shlib-undefined` on its link step).

Availability (conda-forge, confirmed via the solver / anaconda.org API):

- `mpich`, `openmpi`: `linux-64/aarch64`, `osx-64/arm64` — **not `win-64`**.
- `gcc`/`gxx`/`gfortran` **and** `clang`/`clangxx`: all of linux + osx (+ win).
  So an all-GNU osx toolchain is available if ever needed.
- `hdf5`, `libnetcdf`, `netcdf-fortran` with `mpi_mpich_*` builds: present on
  `osx-arm64` (and osx-64).
- `psyclone`, `fparser`, `sci-fab`, `metomi-rose`, `cylc-flow`, `cylc-rose`:
  `noarch` — available on every platform.
- `yaxt`: all four platforms, in both `Xt_int` ABIs (conda-forge/yaxt-feedstock#6).

[`conda-forge-pinning-feedstock`]: https://github.com/conda-forge/conda-forge-pinning-feedstock/blob/main/recipe/conda_build_config.yaml
