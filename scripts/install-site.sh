#!/usr/bin/env bash
# scripts/install-site.sh -- bootstrap a conda environment for one site.
#
# The environment is site-neutral: the same packages on a laptop and on an HPC
# system. What a site adds is its Cylc platforms and Rose site config (see
# docs/site-config.md). This script copies one site's files from sites/<site>/
# into the environment, and drops an activation hook into it, so that every later
# `activate` (and `micromamba run`, and a Cylc job that activates the env) points
# Cylc and Rose at them. Run it once per environment; nothing else changes.
#
#     micromamba create -n lfric-env -f envs/lfric-env.yaml
#     micromamba run -n lfric-env scripts/install-site.sh isambard3
#
# or, from an activated environment:
#
#     scripts/install-site.sh isambard3
#
# Usage: install-site.sh [--prefix <env-prefix>] <site>
#        install-site.sh [--prefix <env-prefix>] --remove
#        install-site.sh --list
#
# The prefix defaults to $CONDA_PREFIX. Installing again replaces the previous
# site. What it writes into the prefix:
#
#   etc/lfric-site/                         the site's files, copied (not linked,
#                                           so the env survives this repo moving)
#   etc/conda/activate.d/lfric-site.sh      exports CYLC_SITE_CONF_PATH and
#   etc/conda/deactivate.d/lfric-site.sh    ROSE_SITE_CONF_PATH, and undoes it
#
# A variable that is already set when the env is activated is left alone, so a
# site's own login profile or module still wins, as it does for the Spack module.
set -euo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_here/common.sh"

SITES_DIR="$REPO_ROOT/sites"

usage() { sed -n '/^# Usage:/,/^#$/{/^#$/d;s/^# \{0,1\}//;p}' "${BASH_SOURCE[0]}"; }
list_sites() {
  local d
  for d in "$SITES_DIR"/*/; do basename -- "$d"; done
}

prefix="${CONDA_PREFIX:-}"
site=""
remove=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) [ $# -ge 2 ] || die "--prefix needs a path"; prefix="$2"; shift 2 ;;
    --prefix=*) prefix="${1#--prefix=}"; shift ;;
    --remove) remove=1; shift ;;
    --list) list_sites; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option '$1' (see --help)" ;;
    *) [ -z "$site" ] || die "only one site at a time"; site="$1"; shift ;;
  esac
done

[ -n "$prefix" ] || die "no environment: activate it, use 'micromamba run -n <env>', or pass --prefix"
[ -d "$prefix/conda-meta" ] || die "$prefix is not a conda environment (no conda-meta/)"

site_dest="$prefix/etc/lfric-site"
hook_on="$prefix/etc/conda/activate.d/lfric-site.sh"
hook_off="$prefix/etc/conda/deactivate.d/lfric-site.sh"

if [ "$remove" = 1 ]; then
  [ -z "$site" ] || die "--remove takes no site"
  rm -rf -- "$site_dest" "$hook_on" "$hook_off"
  info "Removed the site config from $prefix; it takes effect at the next activation"
  exit 0
fi

[ -n "$site" ] || { usage >&2; die "which site? one of: $(list_sites | paste -sd' ' -)"; }
[ -d "$SITES_DIR/$site" ] || die "no site '$site' in $SITES_DIR (have: $(list_sites | paste -sd' ' -))"

rm -rf -- "$site_dest"
mkdir -p "$site_dest" "$(dirname -- "$hook_on")" "$(dirname -- "$hook_off")"
cp -R "$SITES_DIR/$site/." "$site_dest/"
echo "$site" > "$site_dest/SITE"

# The hooks are sourced by whatever shell activates the env, so they are POSIX sh.
# Each records which variables IT set, so deactivation removes only those.
cat > "$hook_on" <<'EOF'
# Installed by lfric-conda's scripts/install-site.sh: point Cylc and Rose at the
# site config in $CONDA_PREFIX/etc/lfric-site. Values already set are kept.
_lfric_site_dir="$CONDA_PREFIX/etc/lfric-site"
if [ -d "$_lfric_site_dir" ]; then
  LFRIC_SITE_SET=""
  if [ -z "${CYLC_SITE_CONF_PATH:-}" ] && [ -f "$_lfric_site_dir/flow/global.cylc" ]; then
    export CYLC_SITE_CONF_PATH="$_lfric_site_dir"
    LFRIC_SITE_SET="$LFRIC_SITE_SET CYLC_SITE_CONF_PATH"
  fi
  if [ -z "${ROSE_SITE_CONF_PATH:-}" ] && [ -f "$_lfric_site_dir/rose.conf" ]; then
    export ROSE_SITE_CONF_PATH="$_lfric_site_dir"
    LFRIC_SITE_SET="$LFRIC_SITE_SET ROSE_SITE_CONF_PATH"
  fi
  LFRIC_SITE="$(cat "$_lfric_site_dir/SITE" 2>/dev/null || echo unknown)"
  export LFRIC_SITE LFRIC_SITE_SET
fi
unset _lfric_site_dir
EOF

cat > "$hook_off" <<'EOF'
# Installed by lfric-conda's scripts/install-site.sh: undo activate.d/lfric-site.sh.
for _lfric_site_var in ${LFRIC_SITE_SET:-}; do
  unset "$_lfric_site_var"
done
unset _lfric_site_var LFRIC_SITE LFRIC_SITE_SET
EOF

info "Installed site '$site' into $prefix"
info "It takes effect at the next activation (or 'micromamba run'); check with:"
info "  cylc config -i '[platforms]'    rose config rosie-id"
