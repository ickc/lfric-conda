#!/usr/bin/env bash
# scripts/list-channel.sh -- show what the local channel currently holds.
set -euo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_here/common.sh"

[ -d "$LOCAL_CHANNEL" ] || { info "local channel not created yet: $LOCAL_CHANNEL"; exit 0; }

info "Local channel: $LOCAL_CHANNEL"
find "$LOCAL_CHANNEL" -name '*.conda' -o -name '*.tar.bz2' \
  | sed "s|^$LOCAL_CHANNEL/||" | sort \
  || info "(empty)"
