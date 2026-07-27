# The science-suite examples — run a real LFRic suite (Rose/Cylc)

The fullest Stage-2 example: running a real **Rose/Cylc LFRic science suite** on the
conda environment. Scientists run LFRic this way — `cylc` schedules the task graph
(extract → build → mesh → run) and `rose` materialises each task's namelists — so
this example runs it *that* way rather than reinventing it.

> The core of this repo is the **environment** (Stage 1, `recipes/`). These suites
> are not that core — they are things you do *with* it, and templates to copy. They
> are ported from the same examples in [ickc/lfric-env-isambard][spack-repo], which
> ported them from the upstream [Isambard3-LFRic-Env-Science-Suites][upstream].

[spack-repo]: https://github.com/ickc/lfric-env-isambard
[upstream]: https://github.com/UniExeterRSE/Isambard3-LFRic-Env-Science-Suites

Everything the suite needs is already in the environment — `cylc`, `rose`,
`rose_picker`, `psyclone`, the compilers, mpich, XIOS, netCDF — so there is nothing
extra to install: `run-suite.sh` activates it and the tasks use that same `cylc`.

## Run it

```bash
bash scripts/stage-sources.sh                        # once: the LFRic source
micromamba create -n lfric-env -f envs/lfric-env.yaml -c ./local-channel -c conda-forge
micromamba run -n lfric-env bash examples/science-suites/run-suite.sh u-dr932
```

Watch it, or wait for it:

```bash
cylc tui u-dr932                 # interactive
cylc workflow-state u-dr932      # one-shot task states
bash examples/science-suites/run-suite.sh u-dr932 --no-detach   # block until done
```

A successful run ends with the `lfric_atm` task `succeeded`; output lands under
`~/cylc-run/u-dr932/runN/share/output`. To re-run cleanly:
`cylc stop --now u-dr932; cylc clean u-dr932 -y`.

## The suites

| Suite | Science case | Status here |
|-------|--------------|-------------|
| **u-dr932** | GungHo Shallow/Deep Hot Jupiter temperature forcing (idealised, multigrid cubed sphere) | ✅ **builds + runs end-to-end**, in CI on `linux-64` and `linux-aarch64` every push, and locally on Isambard 3 (aarch64). Self-contained: radiation off, analytic initial state, no external data. |

Only this one suite is ported, and that is deliberate. The Spack repo also carries
`u-dn704` (NWP GAL9 @ C12) and `u-dt000` (Uranus/Neptune forcing); neither can be
demonstrated here:

- **u-dn704** needs ~GB of NWP ancillaries, a start dump and `um_aux` ctldata
  staged on disk. It is not runnable on a CI runner, and shipping a suite that
  cannot be run — and therefore cannot be kept working — would be decoration. The
  three site changes below are all it would take, on a machine that has the data.
- **u-dt000** is blocked upstream, on the Spack environment too: its science
  (`theta_forcing='ice_giants_obs_like'`) exists in neither the pinned
  `2026.07.1` (vn3.2) nor the suite's own declared mainline `vn2.2` — it needs a
  fork that the suite does not reference. No environment can fix that.

`u-dr932` is the one that answers the question this repo asks, because it exercises
every layer: rose/cylc drive it, psyclone/rose-picker/fab build it, and
mpich/XIOS/netCDF/HDF5/yaxt/shumlib run it.

## What was adapted (and how little)

Each suite is the upstream Rose/Cylc suite with three site-specific bindings. All
three are *simpler* here than in the Spack port, because a conda environment is
self-contained:

1. **Sources → per-suite offline extract (`dependencies.yaml`).** The suite
   declares the refs it builds; its `extract` task runs
   [`site/extract-sources.sh`](site/extract-sources.sh), which materialises each ref
   **offline** (`git archive`) from this repo's staged `vendor/` mirrors into the
   suite's `SOURCE_ROOT`, then applies the [`patches/`](../../patches) stack there.
   The build reads that per-suite tree, never `vendor/` directly — so a suite can
   build a *different* ref just by editing its `dependencies.yaml` (staging it in
   the mirror first; the extract never fetches).

2. **Env activation → `conda activate`.** [`site/activate-env.sh`](site/activate-env.sh)
   is the suite's `ACTIVATE_ENV`. It is a **thin** activator: it sources
   [`scripts/lfric-env-activate.sh`](../../scripts/lfric-env-activate.sh), which is
   the whole toolchain contract and lives in one place. The Spack port needed
   per-site branches (Isambard 3 / Monsoon / MetO ex1a — each with different module
   systems and Cray PE loads); a conda prefix is the same everywhere, so `flow.cylc`
   here has **one** platform family.

3. **Platform → cylc's built-in `localhost`.** Job runner `background`: no batch
   system, no platform definition, nothing written to `~/.cylc` except (optionally)
   where the run directory goes. The Spack port had to declare an `isambard3`
   Slurm platform. Submit to a batch system instead with
   `-S CYLC_PLATFORM=<your-platform>`.

The launcher follows from (3): [`site/bin/launch-exe`](site/bin/launch-exe) uses
the environment's own `mpiexec` (Hydra colon syntax for a dedicated XIOS server),
where the Spack port used `srun --multi-prog` so cray-mpich would use Slingshot.

### Scale

`rose-suite.conf` ships the **smallest configuration that is still the same
science** — C24 mesh, `TOTAL_RANKS_REQ=6` (one rank per cubed-sphere panel; 6 is
the smallest valid decomposition above 1), and a 2-hour forecast (6 steps at
dt=1200 s). That is what makes it run on a 4-vCPU GitHub runner in minutes. The
full-size configuration this suite was validated at on Isambard 3 is `C48_MG`,
24 ranks, `P1D`:

```bash
bash examples/science-suites/run-suite.sh u-dr932 \
  -S "LFRIC_RES='C48_MG'" -S "TOTAL_RANKS_REQ=24" \
  -S "EXPT_RUNLEN='P1D'" -S "EXPT_RESUB='P1D'"
```

### Version alignment

The pinned LFRic (`2026.07.1` = apps vn3.2) is **newer** than the version these
suites were written for (vn3.0), so their namelists carry the mechanical,
non-science forward-port the Spack repo derived (e.g. `finite_element` gaining
`coord_space`/`coord_order_nonprime`). Those edits came across with the suite; see
[the Spack repo's notes][spack-suites] for how they were derived, since the same
reasoning applies to any suite you port here.

[spack-suites]: https://github.com/ickc/lfric-env-isambard/blob/main/examples/science-suites/README.md

## Adapting this for your own suite

Drop your suite in a new directory here and make the same three bindings:

1. **Sources.** Add a `dependencies.yaml`, point the `extract` task at
   `site/extract-sources.sh`, and set `APPS_ROOT_DIR`/`CORE_ROOT_DIR`/`PHYSICS_ROOT`
   to the **extracted** tree `$SOURCE_ROOT/{lfric_apps,lfric_core,physics}` — not
   `vendor/`.
2. **Env.** Let `run-suite.sh` inject `ACTIVATE_ENV`/`LFRIC_CONDA_ENV`/`REPO_ROOT`,
   and source `ACTIVATE_ENV` in the root `init-script` (before anything else runs —
   a Cylc job shell starts with nothing activated).
3. **Compiler.** Inherit it: `FC = $FC`, `LDMPI = $LDMPI`, `CXX = $CXX`,
   `FPP = $FPP`. Never hard-code `mpif90` — that is what keeps the same suite
   working against either Stage-1 mechanism.

The `site/` glue is reusable as-is; that is the contract between the environment
and a science suite.
