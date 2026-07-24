#!/usr/bin/env bash
# scripts/setup-cylc.sh -- configure cylc for running the science-suite examples.
#
# OPT-IN and OPTIONAL, and deliberately much smaller than its counterpart in the
# sibling Spack repo. There, setup-cylc.sh had to declare an `isambard3` platform
# with `job runner = slurm`, because on a Cray EX the suite's heavy tasks must go
# through the batch system. Here the environment is a conda prefix that runs
# wherever it is installed, so the examples target cylc's built-in `localhost`
# platform (job runner = background) and NO platform definition is needed.
#
# What is left is the one thing cylc cannot guess: WHERE the run directory goes.
# cylc defaults to ~/cylc-run, which on an HPC home (quota'd, often not the right
# filesystem) is the wrong place, and in CI is fine. So this writes, idempotently:
#
#   ~/.cylc/flow/global.cylc     [install][symlink dirs][localhost] run = <base>
#
#   bash scripts/setup-cylc.sh
#
# Env:
#   CYLC_RUN_BASE       run directory  (default $CYLC_RUN_BASE_ROOT/$USER/cylc-run)
#   CYLC_RUN_BASE_ROOT  base for the default run dir (default $PROJECTDIR|$SCRATCH|$HOME)
#   CYLC_USER_CONF      config file    (default ~/.cylc/flow/global.cylc)
#   LFRIC_CYLC_SKIP_SETUP=1  do nothing (CI, where the default ~/cylc-run is right)
set -uo pipefail

info() { echo "INFO: $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

if [ "${LFRIC_CYLC_SKIP_SETUP:-0}" = "1" ]; then
  info "LFRIC_CYLC_SKIP_SETUP=1 -- leaving cylc's defaults alone"
  echo "CYLC_SETUP_OK"
  exit 0
fi

run_base_root="${CYLC_RUN_BASE_ROOT:-${PROJECTDIR:-${SCRATCH:-$HOME}}}"
run_base="${CYLC_RUN_BASE:-$run_base_root/${USER:-$(id -un)}/cylc-run}"
conf="${CYLC_USER_CONF:-$HOME/.cylc/flow/global.cylc}"
conf_dir="$(dirname "$conf")"
run_start="# BEGIN LFRIC_CYLC_RUN_DIR"; run_end="# END LFRIC_CYLC_RUN_DIR"

mkdir -p "$conf_dir" "$run_base" \
  || die "could not create $conf_dir / $run_base (permissions? full filesystem?)"
[ -f "$conf" ] || : > "$conf" || die "could not write $conf"

# Replace our managed block if present, else append it -- so this never disturbs
# anything else the user keeps in global.cylc.
if grep -q "$run_start" "$conf" 2>/dev/null; then
  awk -v s="$run_start" -v e="$run_end" -v run="$run_base" '
    $0==s {inb=1; print; print "[install]"; print "    [[symlink dirs]]";
           print "        [[[localhost]]]"; print "            run = " run; next}
    $0==e {inb=0; print; next} !inb{print}' "$conf" > "$conf.tmp" && mv "$conf.tmp" "$conf"
else
  cat >> "$conf" <<EOF

$run_start
[install]
    [[symlink dirs]]
        [[[localhost]]]
            run = $run_base
$run_end
EOF
fi
info "cylc run dir -> $run_base  (in $conf)"

echo "CYLC_SETUP_OK"
