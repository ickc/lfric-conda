# LFRic-source patches

Fixes applied to the **LFRic source** (not to the conda environment) before the
Stage-2 examples compile it. `scripts/patch-all.sh` runs them over the staged
`vendor/` tree; the science-suite examples run the same stack over their own
per-suite extracted tree (`LFRIC_SRC_ROOT`).

| patch | tree | what |
|---|---|---|
| `10-lfric_core-stop-timing-patch.sh` | `lfric_core` | `stop_timing` gained an optional `timing_section_name` argument that callers already pass |
| `11-lfric_core-mpicxx-patch.sh` | `lfric_core` | `cxx/mpic++.mk` identifies the C++ backend from the first word of `mpic++ --version`; normalise wrapper output so a `g++`-backed wrapper is recognised |
| `30-lfric_apps-local-sources-patch.sh` | `lfric_apps` | `get_git_sources.get_source()` clones/rsyncs/fetches science sources mid-build; replace it with a symlink-and-check of the staged tree, so builds are offline and reproducible |
| `31-lfric_apps-slow-physics-mphys-field-patch.sh` | `lfric_apps` | vn3.2 regression: `slow_physics_alg_mod` fetches `dtheta_mphys` unconditionally, but vn3.2 stopped creating the UM-physics fields for forcing-only configs (breaks u-dr932 / u-dt000) |

Every patch is **idempotent** — it looks for its own marker and returns — and
skips cleanly when its target file is absent, so it tolerates ref drift.

## Kept byte-identical to the Spack repo's

These are copies of `patches/*-lfric_*` in
[ickc/lfric-env-isambard](https://github.com/ickc/lfric-env-isambard), with only
the header comments retargeted (staging is `scripts/stage-sources.sh` here, git
submodules there). The **marker strings are deliberately unchanged** — including
the literal `PATCHED (lfric-env-isambard)` and `LFRIC-ENV-ISAMBARD:` text written
into the patched sources. That is what makes the two stacks interoperable: a tree
already patched by one repo is recognised as patched by the other, so pointing
this repo's `minimal-compile` example at the sibling repo's vendored source (which
is exactly how it was first proven) does not double-patch and fail.

Two consequences worth stating plainly:

- **The patched source is the same in both.** Any difference in the Stage-2
  result is therefore attributable to the *environment*, which is the whole point
  of this repo.
- **Patch 31 should disappear.** It is an upstream bug to report; drop it once a
  `2026.07.x` carries the fix.
