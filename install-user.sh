#!/usr/bin/env bash
# install-user.sh — install the pinned toolchains (mise.toml + mise.lock) for the current user, on a
# machine that is not an atc box (the owner's Mac; also works on Linux). No root, nothing shared.
#
#   ./install-user.sh           install/update what mise.lock pins, then the uv tools
#
# Needs, once, in the user's shell startup (the script checks and prints the line):
#   export MISE_GLOBAL_CONFIG_FILE=<this repo>/mise.toml
# With that, mise reads this repo's mise.toml as the user's global config and its mise.lock next to it;
# `mise use -g …` edits this repo's mise.toml; files in ~/.config/mise/conf.d/ still load on top (put
# personal extras and settings such as shims_dir there). Tools with `os = [...]` are skipped elsewhere.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
want=$here/mise.toml
mise=${MISE:-$(command -v mise || true)}
if [[ -z $mise ]]; then
    echo "install-user.sh: mise not on PATH (https://mise.jdx.dev/installing-mise.html)" >&2
    exit 1
fi
if [[ $(id -u) -eq 0 ]]; then
    echo "install-user.sh: not as root; on an atc box use: sudo $here/install.sh" >&2
    exit 1
fi
if [[ ${MISE_GLOBAL_CONFIG_FILE:-} != "$want" ]]; then
    echo "install-user.sh: MISE_GLOBAL_CONFIG_FILE is '${MISE_GLOBAL_CONFIG_FILE:-}'; add this to your shell startup" >&2
    echo "  (e.g. ~/.local/state/zsh/env-local.zsh), open a new shell, and run me again:" >&2
    echo "    export MISE_GLOBAL_CONFIG_FILE=$want" >&2
    exit 1
fi

pinned=$(sed -n 's/^MISE_VERSION=v//p' "$here/install.sh")
have=$("$mise" --version 2>/dev/null | awk '{print $1}')
[[ $have == "$pinned" ]] || echo "install-user.sh: note: mise $have here, $pinned on the boxes" >&2

# Locked: refuse any artifact mise.lock doesn't cover (as install.sh does on the boxes).
MISE_TRUSTED_CONFIG_PATHS=$here MISE_LOCKED=1 MISE_YES=1 "$mise" install
"$mise" reshim

# Python CLI tools, as on the boxes (uv-tools.txt), into the user's own uv tool dir.
uv=$("$mise" which uv)
{ grep -Ev '^[[:space:]]*(#|$)' "$here/uv-tools.txt" || true; } | while IFS= read -r spec; do
    "$uv" tool install --upgrade "$spec"
done

"$mise" ls --current
