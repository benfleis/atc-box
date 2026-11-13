# ccache: C/C++ compiler cache, one dir shared by host and container (Rust stays on sccache,
# RUSTC_WRAPPER). DuckDB's CMake picks ccache over sccache by itself (find_program(ccache sccache)),
# so no CMAKE_*_COMPILER_LAUNCHER here: setting it too would not double-wrap, but it would also
# hijack non-DuckDB projects.
# Env only: CCACHE_CONFIGPATH=/dev/null stops ccache reading $CCACHE_DIR/ccache.conf, which lies in
# sandbox-writable cache/ and could set prefix_command (code the host would run).
export CCACHE_CONFIGPATH=/dev/null
export CCACHE_DIR="$WORKSPACE_ROOT/cache/ccache"
export CCACHE_MAXSIZE=60G
# Rewrite absolute paths under src/ to relative, and keep the cwd out of the hash: what lets a
# second worktree hit the first one's objects.
export CCACHE_BASEDIR="$WORKSPACE_ROOT/src"
export CCACHE_NOHASHDIR=1
# The compiler is the bin/clang++ wrapper script; content hashes it (it names the clang version
# dir), mtime would miss everything each time install.sh rewrites it.
export CCACHE_COMPILERCHECK=content
# A fresh worktree's headers are all "too new" for direct mode by default; DuckDB has no
# __DATE__/__TIME__ and no PCH, so no other sloppiness is needed.
export CCACHE_SLOPPINESS=include_file_mtime,include_file_ctime
