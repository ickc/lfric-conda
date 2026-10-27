# Site configuration: what a site adds to the environment

The conda environment is a toolchain. It is the same on every machine, so it
ships **no site configuration**: no Cylc platforms, no Rose site config, no
rose-stem site. Those are facts about a machine, and a site adds them itself.
This page says what they are, and how to set them up, with Isambard 3 as the
worked example.

The Spack environment in [lfric-env-isambard][spack-repo] is built for one machine,
so its module does ship them. Here, the same files are in
[`examples/site-config/isambard3/`](../examples/site-config/isambard3/) as an
example. Nothing activates them.

[spack-repo]: https://github.com/ickc/lfric-env-isambard

## The three pieces

| piece | what it is for | variable | needed when |
|---|---|---|---|
| Cylc global config | the batch platform(s) a suite submits to, and where run directories live | `CYLC_SITE_CONF_PATH` (the directory above `flow/`) | running a suite through a batch system instead of on `localhost` |
| Rose site config, `[rosie-id]` | the `u-` prefix map, so `rosie checkout u-...` works | `ROSE_SITE_CONF_PATH` | getting suites from MOSRS, at any site outside the Met Office |
| Rose site config, `[rose-stem]` + an lfric_apps rose-stem site | `SITE=<name>`, and the `rose-stem/site/<name>/` it selects | `ROSE_SITE_CONF_PATH`, plus a change to your lfric_apps clone | running lfric_apps rose-stem |

A user's own `~/.cylc/flow/global.cylc` and `~/.metomi/rose.conf` are merged on top
of the site files and win, so a site config never takes anything away from a user.

## Without any of it

The examples in this repo need none of the three. u-dr932 runs on Cylc's
`localhost` platform (background jobs, `mpiexec`), which needs no platform
definition. `scripts/setup-cylc.sh` optionally points the run directories at a
larger filesystem, in your own `~/.cylc`. That is enough for one node.

## Bootstrapping a site, using Isambard 3 as the example

1. **Cylc platform.** Copy
   [`isambard3/flow/global.cylc`](../examples/site-config/isambard3/flow/global.cylc)
   to `<site-dir>/flow/global.cylc` and change the platform: its name, `job runner`
   (`slurm`, `pbs`, ...) and, for a remote batch host, `hosts` and
   `install target`. Then `export CYLC_SITE_CONF_PATH=<site-dir>`. Check it with
   `cylc config -i '[platforms][<name>]'`. Submit a suite's tasks there with
   `-S CYLC_PLATFORM=<name>`.
2. **rosie.** Copy
   [`isambard3/rose.conf`](../examples/site-config/isambard3/rose.conf)'s
   `[rosie-id]` section into `<site-dir>/rose.conf`, and
   `export ROSE_SITE_CONF_PATH=<site-dir>`. It is the same for every site.
3. **rose-stem.** lfric_apps' rose-stem only knows the sites in its
   `rose-stem/site/`. Isambard 3 is not one of them yet. lfric-env-isambard carries
   it as a patch to an lfric_apps clone (`patches/rose-stem/`, against lfric_apps
   `main`), and upstreaming it to MetOffice/lfric_apps is tracked in
   ickc/lfric-env-isambard#32. For another site, start from the closest
   existing `rose-stem/site/*`. Then set `[rose-stem] automatic-options=SITE=<name>`
   in the same `rose.conf`.

To make it automatic, export the two variables from the site's own login profile or
module, not from this environment's activation: the environment stays the same
everywhere.

## The MOSRS suites

lfric-env-isambard also runs three suites from MOSRS (u-dn704, u-dt000, u-dz791).
They are not ported here. CI cannot reach MOSRS, and each port depends on the site
(platform, data). The one suite this repo runs, u-dr932, comes from a public repo,
so CI can run it end to end. To run the MOSRS ones on Isambard 3, use
lfric-env-isambard.
