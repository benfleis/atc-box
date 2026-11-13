#!/usr/bin/env bash
# lock.sh — regenerate mise.lock after editing mise.toml (TOOLING.md). Any user, Linux or macOS; only this
# directory's mise.lock changes. It locks every platform in mise.toml's `lockfile_platforms`.
# Extra args go to `mise lock` (e.g. --bump uv).
#
# mise: $MISE, else the `mise` on PATH, else the box's pinned copy in /opt/tooling. The lock format follows
# the mise that writes it, so the boxes' pinned mise (MISE_VERSION in install.sh) must be able to read it:
# a mismatch is a warning here; bump MISE_VERSION when you lock with a newer mise.
# GitHub API limits: set MISE_GITHUB_TOKEN (or GITHUB_TOKEN) to lock without hitting 60 requests/hour.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
pinned=$(sed -n 's/^MISE_VERSION=v//p' "$here/install.sh")
mise=${MISE:-$(command -v mise || true)}
[[ -n $mise ]] || mise=${TOOLING_ROOT:-/opt/tooling}/mise/mise-v$pinned
if [[ ! -x $mise ]]; then
    echo "lock.sh: no mise (set MISE=…, put mise on PATH, or run install.sh on a box)" >&2
    exit 1
fi
have=$("$mise" --version 2>/dev/null | awk '{print $1}')
if [[ $have != "$pinned" ]]; then
    echo "lock.sh: warning: locking with mise $have, the boxes install with $pinned (install.sh MISE_VERSION)" >&2
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Isolated from the caller's own mise config and installs; only the download/metadata cache is shared.
# On a box that is /opt/mise/cache (shared with install.sh), elsewhere the user's normal mise cache.
cache=${TOOLING_MISE_CACHE:-}
if [[ -z $cache ]]; then
    if [[ -w /opt/mise/cache ]]; then cache=/opt/mise/cache
    else cache=${XDG_CACHE_HOME:-$HOME/.cache}/mise; fi
fi
export MISE_DATA_DIR=$tmp/data MISE_STATE_DIR=$tmp/state MISE_CACHE_DIR=$cache \
    MISE_CONFIG_DIR=$tmp/config MISE_GLOBAL_CONFIG_FILE=$tmp/config/none.toml \
    MISE_TRUSTED_CONFIG_PATHS=$here MISE_YES=1
cd "$here" && "$mise" lock "$@"
chmod 0644 "$here/mise.lock"
