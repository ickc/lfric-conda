#!/usr/bin/env bash
# scripts/patch-all.sh -- apply the LFRic-source patch stack to the staged tree.
#
# STAGE 2 ONLY (see scripts/stage-sources.sh). The patches in patches/ fix things
# in the LFRic source itself that neither the Spack nor the conda environment can
# fix from the outside; they are the same stack the sibling Spack repo applies, so
# both Stage-2 examples compile identical source.
#
# Every patch is idempotent (it detects its own marker and returns) and skips
# cleanly when its target file is absent, so re-running is safe.
#
#   bash scripts/patch-all.sh                    # patch vendor/
#   LFRIC_SRC_ROOT=/some/tree bash scripts/patch-all.sh
#
# LFRIC_SRC_ROOT is the directory *containing* lfric_apps/ and lfric_core/ --
# vendor/ by default, or a science suite's per-suite extracted tree (which is why
# examples/science-suites/site/extract-sources.sh applies the same patches with
# LFRIC_SRC_ROOT pointed at $SOURCE_ROOT).
set -euo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_here/common.sh"

SRC_ROOT="${LFRIC_SRC_ROOT:-${LFRIC_VENDOR_DIR:-$REPO_ROOT/vendor}}"
[ -d "$SRC_ROOT" ] || die "no source tree at $SRC_ROOT (run: bash scripts/stage-sources.sh)"

info "patching $SRC_ROOT"
shopt -s nullglob
n=0
for p in "$REPO_ROOT"/patches/*-patch.sh; do
  info "  $(basename "$p")"
  LFRIC_SRC_ROOT="$SRC_ROOT" bash "$p" || die "patch failed: $p"
  n=$((n + 1))
done
[ "$n" -gt 0 ] || die "no patches found under $REPO_ROOT/patches"

info "applied $n patch(es)"
echo "PATCH_ALL_OK"
