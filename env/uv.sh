# uv: its Python lives here, installed by install.sh and read-only to both sides, so a venv
# built on either side finds its interpreter on the other (TOOLING.md). Shared tools come from
# install.sh (uv-tools.txt), not UV_TOOL_DIR: uv locks that dir on every tool command, even uvx.
# A read-only mount fails the lock.
export UV_CACHE_DIR="$WORKSPACE_ROOT/cache/uv"
export UV_PYTHON_INSTALL_DIR="$TOOLING_ROOT/uv-python"
export UV_PYTHON_DOWNLOADS=never
# Only uv's own Pythons: a distro Python (/usr/bin/python3) differs per OS, so a venv on it
# works on one side only.
export UV_PYTHON_PREFERENCE=only-managed
