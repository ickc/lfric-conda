# Site configuration: what a site adds to the environment

The conda environment is a toolchain. Its packages are the same on every machine,
so they carry **no site configuration**: no Cylc platforms, no Rose site config,
no rose-stem site. Those are facts about a machine. This repo keeps them per site
in [`sites/`](../sites/), and one command installs a site's files into an
environment:

```sh
micromamba create -n lfric-env -f envs/lfric-env.yaml
micromamba run -n lfric-env scripts/install-site.sh isambard3
```

That is the whole deployment on Isambard 3. On a laptop, or any machine without a
site in `sites/`, skip the second line: nothing in this repo's examples needs it.

The Spack environment in [lfric-env-isambard][spack-repo] is built for one machine,
so its module ships the same files and sets the same variables. `sites/isambard3/`
has the same content.

[spack-repo]: https://github.com/ickc/lfric-env-isambard

## What `install-site.sh` does

It copies `sites/<site>/` into the environment at `etc/lfric-site/`, and drops an
activation hook into `etc/conda/{activate,deactivate}.d/lfric-site.sh`. From then
on, activating the environment (`micromamba activate`, `micromamba run`, or a Cylc
job that activates it through `scripts/lfric-env-activate.sh`) exports:

| variable | points at | read by |
|---|---|---|
| `CYLC_SITE_CONF_PATH` | `$CONDA_PREFIX/etc/lfric-site` (containing `flow/global.cylc`) | Cylc |
| `ROSE_SITE_CONF_PATH` | `$CONDA_PREFIX/etc/lfric-site` (containing `rose.conf`) | Rose, rosie, rose-stem |
| `LFRIC_SITE` | the site's name | informational |

A variable that is already set at activation is left alone, so a site's own login
profile or module still wins, as it does with the Spack module. Deactivating
unsets only what the hook set. The files are copied, not linked, so the
environment does not depend on this checkout afterwards.

```sh
scripts/install-site.sh --list              # the sites this repo carries
scripts/install-site.sh isambard3           # from an activated environment
scripts/install-site.sh --prefix <env> isambard3
scripts/install-site.sh --remove            # back to site-neutral
```

Installing again replaces the previous site. The hooks are POSIX sh, so they run
under bash, zsh and sh activations; fish and csh activations do not run them.

## The three pieces

| piece | what it is for | needed when |
|---|---|---|
| Cylc global config, `flow/global.cylc` | the batch platform(s) a suite submits to, and where run directories live | running a suite through a batch system instead of on `localhost` |
| Rose site config, `[rosie-id]` | the `u-` prefix map, so `rosie checkout u-...` works | getting suites from MOSRS, at any site outside the Met Office |
| Rose site config, `[rose-stem]` + an lfric_apps rose-stem site | `SITE=<name>`, and the `rose-stem/site/<name>/` it selects | running lfric_apps rose-stem |

A user's own `~/.cylc/flow/global.cylc` and `~/.metomi/rose.conf` are merged on top
of the site files and win, so a site config never takes anything away from a user.

Isambard 3's, in [`sites/isambard3/`](../sites/isambard3/):

- **Cylc**: a platform `isambard3` (Slurm on the local host). Submit a suite's
  tasks there with `-S CYLC_PLATFORM=isambard3`; the examples default to
  `localhost`. Run directories go under `$PROJECTDIR/$USER` when `PROJECTDIR` is
  set, because `$HOME` is small.
- **rosie**: the standard `u` prefix map. It is the same at every site; reading
  roses-u still needs a MOSRS account.
- **rose-stem**: `SITE=isambard3`. lfric_apps' rose-stem only knows the sites in
  its `rose-stem/site/`, and Isambard 3 is not one of them yet. lfric-env-isambard
  carries it as a patch to an lfric_apps clone (`patches/rose-stem/`, against
  lfric_apps `main`); upstreaming it to MetOffice/lfric_apps is tracked in
  ickc/lfric-env-isambard#32. Until then, apply that patch to your clone, or
  remove the `[rose-stem]` section.

## Adding a site

1. Copy `sites/isambard3/` to `sites/<name>/`.
2. In `flow/global.cylc`, change the platform: its name, `job runner` (`slurm`,
   `pbs`, ...) and, for a remote batch host, `hosts` and `install target`. Keep or
   drop the run-directory block.
3. In `rose.conf`, keep `[rosie-id]` as is. Set `[rose-stem] automatic-options` to
   the closest existing lfric_apps `rose-stem/site/*`, or your own, or drop it.
4. `scripts/install-site.sh <name>`, then check:
   `cylc config -i '[platforms][<name>]'` and `rose config rosie-id`.

Either file may be left out; the hook only sets the variable for the files that
exist. Please send a PR for a site others use.

## Without any of it

The examples in this repo need none of it. u-dr932 runs on Cylc's `localhost`
platform (background jobs, `mpiexec`), which needs no platform definition.
`scripts/setup-cylc.sh` optionally points the run directories at a larger
filesystem, in your own `~/.cylc`. That is enough for one node.

## The MOSRS suites

lfric-env-isambard also runs three suites from MOSRS (u-dn704, u-dt000, u-dz791).
They are not ported here. CI cannot reach MOSRS, and each port depends on the site
(platform, data). The one suite this repo runs, u-dr932, comes from a public repo,
so CI can run it end to end. To run the MOSRS ones on Isambard 3, use
lfric-env-isambard.
