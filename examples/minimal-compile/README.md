# The minimal-compile example — build a science target on the environment

The smallest Stage-2 example: compile the apps-tier science target `lfric_atm`
against the conda Stage-1 environment. No science run — for that see
[`../science-suites/`](../science-suites/README.md).

It is the conda analogue of `examples/minimal-compile/build.sh` in
[ickc/lfric-env-isambard][spack-repo], and its job is to prove one thing: **once
the environment exists, LFRic is compiled exactly the same way, with no Spack and
no Lmod.**

[spack-repo]: https://github.com/ickc/lfric-env-isambard

## Run it

```bash
bash scripts/stage-sources.sh && bash scripts/patch-all.sh   # once: the LFRic source
micromamba create -n lfric-env -f envs/lfric-env.yaml -c ./local-channel -c conda-forge
micromamba run -n lfric-env bash examples/minimal-compile/build.sh
```

A successful run ends with `LFRIC_ATM_OK` and leaves a ~98 MB binary at
`vendor/lfric_apps/applications/lfric_atm/bin/lfric_atm`, linking the
environment's `yaxt` / `netcdf` / `mpich` / `hdf5`. The (large, transient) build
tree goes to `output/lfric_atm_build/`, which is gitignored.

## What it does

1. Sources [`scripts/lfric-env-activate.sh`](../../scripts/lfric-env-activate.sh) —
   the activation contract. That one file is the whole toolchain setup; this
   example adds none of its own.
2. Checks the LFRic source is staged **and patched** (an unpatched tree would let
   `local_build.py` clone sources mid-build, which silently defeats the pins).
3. Runs `python build/local_build.py lfric_atm`, the same entry point LFRic's own
   suites use.

## Adapting it

| want | do |
|---|---|
| a different target | change `lfric_atm` in the `local_build.py` line |
| a different source tree | `LFRIC_APPS_ROOT` / `LFRIC_CORE_ROOT` / `PHYSICS_ROOT`, or `LFRIC_SRC_REPO` to borrow another repo's `vendor/` wholesale |
| more/less parallelism | `MAKE_JOBS` (defaults to `nproc`, capped at 16) |
| a different PSyclone optimisation set | `PSYCLONE_TRANSFORMATION` (default `minimum`; the science suite uses `meto-ex1a`) |
| build somewhere else | `WORK_DIR` |
