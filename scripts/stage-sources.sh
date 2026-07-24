#!/usr/bin/env bash
# scripts/stage-sources.sh -- clone the pinned LFRic science source into vendor/.
#
# STAGE 2 ONLY. Building the conda packages (Stage 1) needs none of this; the
# Stage-2 examples do, because they compile real LFRic source. This is the conda
# analogue of `git submodule update --init` in the sibling Spack repo: it
# materialises the six MetOffice repos at the refs pinned in ./sources.yaml.
#
#   vendor/lfric_apps          vendor/physics/casim   vendor/physics/socrates
#   vendor/lfric_core          vendor/physics/jules   vendor/physics/ukca
#
# All six are PUBLIC and clone anonymously over HTTPS, so this needs no
# credentials -- which is what lets CI run the Stage-2 examples.
#
# The clones double as the LOCAL MIRRORS the science-suite examples extract from
# offline (examples/science-suites/site/extract-sources.sh does `git archive`
# against them), so this is the only step that touches the network.
#
#   bash scripts/stage-sources.sh              # all repos in sources.yaml
#   bash scripts/stage-sources.sh lfric_core   # just these
#
# Env:
#   LFRIC_SOURCES_FILE  pin file to read           (default $REPO_ROOT/sources.yaml)
#   LFRIC_VENDOR_DIR    where to clone into        (default $REPO_ROOT/vendor)
#   LFRIC_SOURCE_DEPTH  git clone depth; 0 = full  (default 1)
#       depth 1 is the cheap CI default and is enough to build the pinned ref.
#       Use 0 when you want the mirror to carry other refs, so a suite's
#       dependencies.yaml can select one offline.
#   LFRIC_STAGE_JOBS    parallel clones            (default 4)
set -euo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_here/common.sh"

SOURCES_FILE="${LFRIC_SOURCES_FILE:-$REPO_ROOT/sources.yaml}"
VENDOR_DIR="${LFRIC_VENDOR_DIR:-$REPO_ROOT/vendor}"
DEPTH="${LFRIC_SOURCE_DEPTH:-1}"
JOBS="${LFRIC_STAGE_JOBS:-4}"

[ -f "$SOURCES_FILE" ] || die "no pin file at $SOURCES_FILE"
command -v git >/dev/null 2>&1 || die "git is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required to read $SOURCES_FILE"

# Where each repo is staged. Mirrors the sibling Spack repo's vendor/ layout, so
# the same *_ROOT_DIR wiring works in both.
dest_for() {
  case "$1" in
    lfric_apps|lfric_core)     echo "$VENDOR_DIR/$1" ;;
    casim|jules|socrates|ukca) echo "$VENDOR_DIR/physics/$1" ;;
    *)                         echo "" ;;
  esac
}

# Clone (or verify) ONE repo at its pinned ref. Idempotent: if the checkout is
# already at the pinned commit it does nothing, so re-running is cheap and a
# CI cache of vendor/ is honoured.
stage_one() {
  local name="$1" ref="$2" source="$3" dest
  dest="$(dest_for "$name")"
  if [ -z "$dest" ]; then
    warn "skip '$name' -- not an LFRic source repo this repo stages"
    return 0
  fi
  [ -n "$ref" ]    || { echo "ERROR: no ref pinned for '$name' in $SOURCES_FILE" >&2; return 1; }
  [ -n "$source" ] || { echo "ERROR: no source URL for '$name' in $SOURCES_FILE" >&2; return 1; }

  if git -C "$dest" rev-parse --git-dir >/dev/null 2>&1; then
    local have want
    have="$(git -C "$dest" rev-parse HEAD)"
    want="$(git -C "$dest" rev-parse --verify --quiet "${ref}^{commit}" || true)"
    if [ -n "$want" ] && [ "$have" = "$want" ]; then
      info "$name already at $ref ($(git -C "$dest" describe --tags --always HEAD 2>/dev/null || echo "$have"))"
      return 0
    fi
    info "$name: re-staging at $ref (was $have)"
    rm -rf "$dest"
  fi

  mkdir -p "$(dirname "$dest")"
  local depth_args=()
  [ "$DEPTH" != "0" ] && depth_args=(--depth "$DEPTH")
  info "clone $name @ $ref"
  # --branch takes a tag or a branch. A raw commit SHA needs the init+fetch path
  # below (GitHub allows fetching a SHA directly).
  if ! git clone --quiet "${depth_args[@]}" --branch "$ref" "$source" "$dest" 2>/dev/null; then
    rm -rf "$dest"
    mkdir -p "$dest"
    git -C "$dest" init --quiet
    git -C "$dest" remote add origin "$source"
    git -C "$dest" fetch --quiet "${depth_args[@]}" origin "$ref" \
      || { echo "ERROR: cannot fetch '$ref' from $source for '$name'" >&2; return 1; }
    git -C "$dest" checkout --quiet FETCH_HEAD
  fi
  info "$name -> $dest ($(git -C "$dest" rev-parse --short HEAD))"
}

want=("$@")
selected() {
  [ "${#want[@]}" -eq 0 ] && return 0
  local n
  for n in "${want[@]}"; do [ "$n" = "$1" ] && return 0; done
  return 1
}

info "pins:   $SOURCES_FILE"
info "vendor: $VENDOR_DIR  (depth=$DEPTH)"
pids=(); n=0; rc=0
while IFS=$'\t' read -r name ref source; do
  [ -n "$name" ] || continue
  selected "$name" || continue
  stage_one "$name" "$ref" "$source" &
  pids+=($!)
  n=$((n + 1))
  # Bounded concurrency: a login node caps processes per user, and four parallel
  # clones already saturate a typical link.
  if [ "${#pids[@]}" -ge "$JOBS" ]; then
    wait "${pids[0]}" || rc=1
    pids=("${pids[@]:1}")
  fi
done < <(python3 "$_here/read-deps.py" "$SOURCES_FILE")

for p in "${pids[@]}"; do wait "$p" || rc=1; done
[ "$rc" -eq 0 ] || die "one or more repos failed to stage"
[ "$n" -gt 0 ] || die "nothing staged -- no matching repos in $SOURCES_FILE"

info "staged $n repo(s). Next: bash scripts/patch-all.sh"
echo "STAGE_SOURCES_OK"
