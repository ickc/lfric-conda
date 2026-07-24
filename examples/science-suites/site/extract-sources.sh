#!/usr/bin/env bash
# examples/science-suites/site/extract-sources.sh -- per-suite OFFLINE LFRic source
# extraction (the "dependencies.yaml" mechanism).
#
# Reads a suite's dependencies.yaml and materialises each declared repo@ref from
# this repo's STAGED MIRRORS (vendor/lfric_apps, vendor/lfric_core,
# vendor/physics/{casim,jules,socrates,ukca}) into SOURCE_ROOT -- with NO network.
# It then applies the LFRic-source patch stack to the extracted tree.
#
# Why this exists: the build must be reproducible and offline, but a suite still
# needs to say WHICH ref of each repo it builds -- that is its science. So the ref
# is declared per suite and extracted from the local mirror via `git archive`.
# This is the upstream-native dependencies.yaml axis, made offline.
#
# OFFLINE CONTRACT: a ref is extractable iff it is already in the local mirror.
# This script NEVER fetches. scripts/stage-sources.sh clones at depth 1 by default,
# so the mirror carries exactly the ref pinned in sources.yaml; to build a
# different ref, stage it once, online:
#   LFRIC_SOURCE_DEPTH=0 bash scripts/stage-sources.sh          # full history, or
#   git -C vendor/lfric_apps fetch --tags origin                # one more mainline ref
#   git -C vendor/lfric_apps remote add <fork> <url> && git -C vendor/lfric_apps fetch <fork>
# A missing ref is a hard error naming exactly what to stage.
#
# Usage:  extract-sources.sh <dependencies.yaml> <SOURCE_ROOT> [REPO_ROOT]
set -euo pipefail

DEPS="${1:?usage: extract-sources.sh <dependencies.yaml> <SOURCE_ROOT> [REPO_ROOT]}"
SOURCE_ROOT="${2:?usage: extract-sources.sh <dependencies.yaml> <SOURCE_ROOT> [REPO_ROOT]}"
REPO_ROOT="${3:-${REPO_ROOT:-}}"

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "INFO: extract-sources: $*"; }

[ -f "$DEPS" ]      || die "dependencies.yaml not found: $DEPS"
[ -n "$REPO_ROOT" ] || die "REPO_ROOT not set (pass as \$3 or env)"
VENDOR_DIR="${LFRIC_VENDOR_DIR:-$REPO_ROOT/vendor}"
[ -d "$VENDOR_DIR" ] || die "no staged mirrors at $VENDOR_DIR (run: bash scripts/stage-sources.sh)"
command -v python3 >/dev/null 2>&1 || die "python3 required to parse dependencies.yaml"

# Mirror path for a repo name; empty => not an LFRic-source repo we stage.
mirror_for() {
  case "$1" in
    lfric_apps|lfric_core)       echo "$VENDOR_DIR/$1" ;;
    casim|jules|socrates|ukca)   echo "$VENDOR_DIR/physics/$1" ;;
    *)                           echo "" ;;
  esac
}
# Where each repo is extracted to (the layout flow.cylc's *_ROOT_DIR expect).
dest_for() {
  case "$1" in
    lfric_apps)                  echo "$SOURCE_ROOT/lfric_apps" ;;
    lfric_core)                  echo "$SOURCE_ROOT/lfric_core" ;;
    casim|jules|socrates|ukca)   echo "$SOURCE_ROOT/physics/$1" ;;
  esac
}

info "dependencies: $DEPS"
info "SOURCE_ROOT:  $SOURCE_ROOT"
mkdir -p "$SOURCE_ROOT"

n=0
while IFS=$'\t' read -r name ref _source; do
  [ -n "$name" ] || continue
  mirror="$(mirror_for "$name")"
  if [ -z "$mirror" ]; then
    info "skip '$name' (not an LFRic-source repo this repo stages)"; continue
  fi
  git -C "$mirror" rev-parse --git-dir >/dev/null 2>&1 \
    || die "mirror for '$name' not staged: $mirror (run: bash scripts/stage-sources.sh)"
  [ -n "$ref" ] || die "no ref declared for '$name' in $DEPS"

  # Resolve the declared ref to a commit IN THE LOCAL MIRROR. No fetch.
  commit="$(git -C "$mirror" rev-parse --verify --quiet "${ref}^{commit}" || true)"
  if [ -z "$commit" ]; then
    die "ref '$ref' for '$name' is NOT in the local mirror ($mirror).
       Offline extraction needs it staged first -- see the header of this script.
       (This script never fetches: that is the offline invariant.)"
  fi

  dest="$(dest_for "$name")"
  info "extract $name @ $ref ($(git -C "$mirror" describe --tags --always "$commit" 2>/dev/null || echo "$commit")) -> $dest"
  rm -rf "$dest"; mkdir -p "$dest"
  git -C "$mirror" archive "$commit" | tar -x -C "$dest"
  n=$((n + 1))
done < <(python3 "$REPO_ROOT/scripts/read-deps.py" "$DEPS")

[ "$n" -gt 0 ] || die "no source repos extracted from $DEPS"
info "extracted $n source repo(s)"

# Apply the LFRic-source patch stack to the EXTRACTED tree (not vendor/). The
# patches are idempotent and skip cleanly when a target file is absent, so they
# tolerate ref-to-ref drift.
LFRIC_SRC_ROOT="$SOURCE_ROOT" bash "$REPO_ROOT/scripts/patch-all.sh" \
  || die "patch stack failed on $SOURCE_ROOT"
info "patch stack applied to $SOURCE_ROOT"
echo "EXTRACT_SOURCES_OK"
