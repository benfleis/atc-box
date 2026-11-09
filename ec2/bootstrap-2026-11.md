# atc-box-1 bootstrap (run by the owner on NEW, as bfleis; MIGRATION, 2026-11-06)

Paste step by step; each block is safe to re-run. Inputs already on NEW: `/opt/workspace` (rsync pass 1),
`/opt/migration-in/home-export-2026-11-06.tgz` (pi settings + sessions, herdr config, mise config, atc cursors,
`.zshrc`/`.zprofile`, symlinks for `.config/{zsh,nvim,git}`) and `home-export-2-src.tgz` (`~/src/fz.sh`,
`~/src/z.lua`). Not exported on purpose: `~/.aws`, `~/.ssh` keys, `.claude`, `.codex`, `.pi/agent/auth.json`,
`~/.local/state/zsh/env-local.zsh` (GH_TOKEN, `AWS_PROFILE=admin`), nvim undo/state, herdr sessions.

## 1. Home

```sh
cd ~ && tar xzf /opt/migration-in/home-export-2026-11-06.tgz && tar xzf /opt/migration-in/home-export-2-src.tgz
mkdir -p ~/src && ln -sfn /opt/workspace/config/dotfiles ~/src/dotfiles
cd ~/src/dotfiles && ./install.sh                  # must run from the dotfiles dir (links use $PWD); warns 'mise/herdr not found' until step 3
ls -la ~/.config/zsh ~/.config/nvim ~/.config/git  # should point into /opt/workspace/config/dotfiles
```

Check that `~/.zshenv` is the dotfiles one (it sets `ZDOTDIR=~/.config/zsh`; without it zsh reads the
dev-desktop `~/.zshrc` instead of `config/zsh/.zshrc`: no HISTFILE, wrong prompt, no dotfiles env):

```sh
ls -la ~/.zshenv                                   # want: .zshenv -> src/dotfiles/.zshenv
ln -sfn src/dotfiles/.zshenv ~/.zshenv             # if not
cp /opt/migration-in/zsh-history.filtered ~/.local/state/zsh/history   # OLD's history minus 1 entry with AWS keys
```

The exported `~/.zshrc` is OLD's corp dev-desktop default: it sets `AWS_EC2_METADATA_DISABLED=true` (which
hides the instance role), Brazil aliases, `~/.toolbox/bin`, an `ssh()` wrapper. On NEW:

```sh
sed -i '/AWS_EC2_METADATA_DISABLED/d' ~/.zshrc     # required
mv ~/.zshrc ~/.zshrc.dev-desktop                     # optional, once a new shell works without it
```

New `env-local.zsh` for this box (no admin profile, no token yet; the instance role is the default credential):

```sh
mkdir -p ~/.local/state/zsh && umask 077 && cat > ~/.local/state/zsh/env-local.zsh <<'E'
# atc-box-1: AWS comes from the instance role (IMDS); no AWS_PROFILE. GitHub tokens: later (atc-tasks setup).
export AWS_REGION=eu-west-1
E
```

## 2. Shared toolchains (`/opt/tooling`, root, read-only to you)

```sh
sudo /opt/workspace/src/iso-claude/tooling/install.sh   # ~10-15 min; rust, uv, go, sccache, clang, mold, herdr, …
ls /opt/tooling/bin | head
```

## 3. Your mise tools (pi, claude, codex, gh, aws-cli, node, herdr, mosh, …)

```sh
curl -fsSL https://mise.run | sh
exec zsh -l
~/.local/bin/mise install            # reads ~/.config/mise/config.toml + mise.lock from the export
mise install mosh@1.4.0              # not `mise use -g`: the multi-platform mise.lock has no windows build of conda:mosh
command -v pi herdr mosh-server aws  # pi comes from /opt/tooling/bin (step 2), the rest from mise shims in ~/.local/bin
(cd ~/src/dotfiles && ./install.sh)         # second run: now finds mise + herdr (tool install, herdr skill)
```

Then from the laptop. `~/.local/bin/mosh-server` is a mise shim that fails (mosh is not in `config.toml`), so point at the real binary, and install the English locale the laptop sends (`sudo dnf install -y glibc-langpack-en`):
`mosh -p 60001:60010 --server=$HOME/.local/share/mise/installs/mosh/1.4.0/bin/mosh-server <user>@79.125.19.247`. Older suggestion:
`mosh --server="$(ssh bfleis@79.125.19.247 'zsh -lc "mise which mosh-server"')" bfleis@79.125.19.247`, or
add `~/.local/share/mise/shims` to PATH in `.zshenv` for non-interactive shells.

## 4. Checks

```sh
aws sts get-caller-identity --query Arn --output text        # assumed-role/atc-box/i-08d4040d314849c5d
aws bedrock-runtime converse --model-id eu.anthropic.claude-opus-5-5 \
  --messages '[{"role":"user","content":[{"text":"say ok"}]}]' --query 'output.message.content[0].text'
cd /opt/workspace && git -C state/tasks status -sb | head -1 && config/atc/bin/atc ready | head -3
pi -p 'say ok'                                               # pi via Bedrock, instance role, no AWS_PROFILE
docker run --rm hello-world | head -2                        # docker group (log out/in once if denied)
```

Then tell MIGRATION: next is the ATC move (freeze on OLD, rsync pass 2, ATC up on NEW from its session).
