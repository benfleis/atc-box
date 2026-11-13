#!/usr/bin/env bash
# install-user.sh — install the pinned toolchains (mise.toml + mise.lock) for the current user, on a
# machine that is not an atc box (the owner's Mac; also works on Linux). No root, nothing shared.
#
#   ./install-user.sh           install/update what mise.lock pins, then the uv tools
#
# Needs, once, in the user's shell startup (the script checks and prints the line):
#   export MISE_GLOBAL_CONFIG_FILE=<this repo>/mise.toml
# With that, mise reads this repo's mise.toml as the user's global config and its mise.lock next to it;
# `mise use -g …` edits this repo's mise.toml and its lock; ~/.config/mise/conf.d/*.toml still loads on top,
# but no tools there (no lock entry: the locked install fails). Personal settings as env vars instead, e.g.
# `export MISE_SHIMS_DIR=~/.local/bin` (mise ignores shims_dir from conf.d). Tools with `os = [...]` are skipped elsewhere.
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

# Locked: refuse any artifact mise.lock doesn't cover (as install.sh does on the boxes). A locked install
# fails as a whole if any global config has a tool without an entry in this lock, so personal tools must not
# live in ~/.config/mise/conf.d (settings only there); a tool for this machine alone goes into mise.toml
# with `os = ["macos"]`, and so into the lock.
# (mise reads conf.d under $HOME/.config/mise and its global config.toml under $XDG_CONFIG_HOME: check both.)
if grep -lE '^[[:space:]]*\[tools' "${MISE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}"/conf.d/*.toml \
    "$HOME"/.config/mise/conf.d/*.toml 2>/dev/null; then
    echo "install-user.sh: the files above add tools outside this repo's lock; move them into $want" >&2
    echo "  (os = [\"macos\"] if only for this machine), leave no [tools] in conf.d, and run me again" >&2
    exit 1
fi
MISE_TRUSTED_CONFIG_PATHS=$here MISE_LOCKED=1 MISE_YES=1 "$mise" install
"$mise" reshim

# Python CLI tools, as on the boxes (uv-tools.txt), into the user's own uv tool dir.
uv=$("$mise" which uv)
{ grep -Ev '^[[:space:]]*(#|$)' "$here/uv-tools.txt" || true; } | while IFS= read -r spec; do
    "$uv" tool install --upgrade "$spec"
done

"$mise" ls --current
