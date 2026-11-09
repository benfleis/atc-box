# atc-box

Everything that builds a box for the ATC model (one ATC, agents, the owner), formerly `iso-claude`. A running
log of how the setup evolved, not a product: expect sharp edges and dated notes.

| path | what |
| --- | --- |
| `mise.toml`, `mise.lock`, `install.sh`, `lock.sh`, `env.sh`, `env/`, `bin/`, `uv-tools.txt` | the shared toolchains in `/opt/tooling`: one root-owned, pinned copy for every user on the box ([TOOLING.md](TOOLING.md)) |
| `docker/` | the iso-agent container (formerly the whole repo): sandboxed Claude/pi/Codex with an egress allowlist ([docker/README.md](docker/README.md)). Not used on the EC2 boxes |
| `ec2/` | first-boot script (`user-data.sh`, keys as placeholders), the 2026-11 runbook and bootstrap notes |
| `iam/` | IAM documents for account 655495220320: live (`*.json`) and proposed/applied after review (`proposed/`) |
| `users/` | the two-user layout (`bfleis` admin, `atc` flight account) and the dotfiles patch for it |

## Install the toolchains

```sh
sudo /opt/workspace/config/atc-box/install.sh     # as root; /opt/tooling must not be writable by users
```

Edit `mise.toml`, run `./lock.sh` (any user; Linux platforms only, see `lockfile_platforms`), then the line
above. `lua` is `conda:lua` (prebuilt; mise's default lua compiles from lua.org, which does not answer from AWS).
Not in mise: `azure-cli` (left out for now).

## Where it lives

`/opt/workspace/config/atc-box`, owned by the admin user and read-only to `atc`: root runs `install.sh` from
here, so no agent may be able to change it. The 2026-11 migration notes behind `ec2/`, `iam/` and `users/`
are in the task notes (`state/tasks/dev-env/migration/`).
