# atc-box-1: two users, `bfleis` and `atc` (proposal, MIGRATION 2026-11-09)

Owner, 2026-11-09: "do this now … bfleis:benfleis (github), and atc:benomatic42 (github), and never let the 2
cross … the exact same dotfiles, but they display prompts differently … I still never put secrets on the box
for bfleis, but it's still a useful abstraction … remote logins to atc regardless, … the primary flight
account, only using bfleis when needed."

## Decision (owner, 2026-11-09)

"I could grant atc root docker access -- then the 2 accounts provide no actual security, since it's
effectively root, but do give me the springboard to switch modes … allow it to be root until we've ironed
out the docker issues. I'll remain steady with no meaningful secrets on the box, at all."

So for now: `atc` is in the `docker` group (root-equivalent), rootful docker stays. The split is structure and
ergonomics, not a boundary, until rootless docker replaces it (TODO `atc-box-1: rootless docker for atc`).
No meaningful secrets on the box for either user.

## Shape

| | `bfleis` (admin) | `atc` (flight account) |
| --- | --- | --- |
| who | you, for sudo/admin only | you day to day, herdr server, ATC, every agent |
| login | `ssh atc-box-admin` (laptop key) | `ssh atc-box` / mosh (same laptop key, or a second one) |
| sudo | yes (NOPASSWD) | **no** |
| docker | none (rootful daemon off) | **rootless** docker, its own daemon and images |
| owns | `/opt/workspace/config/` (dotfiles, atc, pi-atc, pi-nav, AGENTS.md) | `/opt/workspace/{src,state,cache}` |
| GitHub | `benfleis`, nothing stored on the box (owner) | `benomatic42`: own ssh key + fine-grained token, generated on the box |
| AWS | instance role (same as atc: the box is one AWS principal) | instance role (`atc-box`), agents `agent-bedrock` |
| home | `/home/bfleis` 700 | `/home/atc` 700 |

Why `config/` stays `bfleis`-owned: both users load the same dotfiles, `atc` tool, pi extensions and
AGENTS.md from there. If `atc` (= any agent) could write them, every `bfleis` shell and every future ATC
session would run agent-written code (REVIEW-PERIMETER C1). Read-only for `atc`, as `config/` was read-only
in iso. Consequence: ATC and agents cannot edit `config/`; changes there go through you as `bfleis` (as today
in iso). Git in `config/` repos refuses to run as `atc` (owner mismatch), and in `src/`/`state/` as `bfleis`:
that is the separation, never add `safe.directory`.

Never crossing: homes 700; no agent forwarding (sshd `AllowAgentForwarding no`, clients `ForwardAgent no`);
GitHub credentials only in the home of their user; `gh`/git identity per user via `~/.local/state/zsh/env-local.zsh`
(`GIT_AUTHOR_*`/`GIT_COMMITTER_*`; the shared dotfiles' `config/git/config` says `ben fleis
<benfleis@users.noreply.github.com>`, so `atc` must override it). `bfleis` can always `sudo -iu atc`; the
reverse is impossible. That direction is the point.

## Rootless docker: what you give up

From memory unless marked; none of it matters for azurite / ducktest-unitycatalog style test services.
- **No `--privileged`-level power**: no host devices, no kernel modules, no mounting real filesystems
  (NFS/FUSE inside containers is limited), some capabilities absent.
- **Networking** goes through a userspace forwarder (rootlesskit with vpnkit/slirp4netns/pasta): a bit
  slower, published ports < 1024 need a sysctl, the client source IP is not preserved by default,
  `--network host` means the rootless namespace, not the real host.
- **Instance metadata: containers can reach IMDS.** Their traffic leaves through a host process, so the
  hop limit 1 no longer keeps them off it. They get the box's role, i.e. what `atc` has anyway.
- **Resource limits** (`--memory`, `--cpus`) need cgroup v2 delegation via systemd (AL2023 is cgroup v2).
- **Separate image store** per user: images pulled again under `atc`; nothing shared with a root daemon.
- **The daemon runs per user** as a systemd user service: needs `loginctl enable-linger atc` so it runs
  without a login.
- AL2023's repos have no rootless extras (checked on OLD: no `dockerd-rootless-setuptool.sh`, no podman):
  install Docker's static `docker-rootless-extras` for the installed docker version. To verify on NEW.

What you keep: `docker run`/`compose` as usual, test services, builds in containers, volumes in `~atc`.

## Steps (on NEW; you as `bfleis` unless marked; MIGRATION shows each block before you run it)

1. User: `sudo useradd -m -s /bin/zsh atc && sudo chmod 700 /home/atc && sudo loginctl enable-linger atc`;
   check `/etc/subuid` and `/etc/subgid` have an `atc` line (rootless docker needs it).
2. Ownership: `sudo chown -R atc:atc /opt/workspace/src /opt/workspace/state /opt/workspace/cache`;
   `config/` and `/opt/workspace` itself stay `bfleis` 755.
3. sshd: `AllowUsers bfleis atc`; `~atc/.ssh/authorized_keys` = your laptop key (no rrsync line).
4. Docker (for now): `sudo usermod -aG docker atc`; rootful daemon stays. Later (rootless): remove `atc` and
   `bfleis` from `docker`, disable the rootful daemon, rootless extras + `dockerd-rootless-setuptool.sh install`.
5. `atc`'s env (as `atc`): dotfiles `cd /opt/workspace/config/dotfiles && ./install.sh --force`; mise (copy
   `~/.config/mise` from bfleis, the lua build, `uv python install 3.12`, `mise install`); `~/.aws/config` with
   the `atc-box` and `agent-bedrock` profiles; `env-local.zsh` with `AWS_PROFILE=atc-box`, `AWS_REGION`, git
   identity; `~/.pi` moved from `~bfleis` (sessions, settings).
6. GitHub for `atc`: `ssh-keygen` on the box → add to `benomatic42`; fine-grained token (atc-tasks: contents
   RW; forks later) in `gh` (`~atc/.config/gh`).
7. Prompt: a dotfiles change so `atc` looks different (below). Owner commits it in `config/dotfiles`.
8. Laptop `~/.ssh/config`: `Host atc-box` (User atc) and `Host atc-box-admin` (User bfleis).
9. Then: herdr server and ATC start as `atc`. Update user-data/bootstrap docs so the next box does all this.

Prompt sketch for `config/zsh/prompts.zsh` (it already shows `user@host` when `$USERNAME` is not `ben`):

```zsh
[[ $USERNAME = atc ]] && user_at_host='%K{#003040}%F{#00D0FF} atc %k%F{#FF7F50}@%m%f'
[[ $USERNAME = bfleis && $HOST = atc-box* ]] && user_at_host='%K{#401000}%F{#FFC000} ADMIN %k%F{#FF7F50}@%m%f'
```

## Open

- Commit authorship as `atc`: `benomatic42 <…@users.noreply.github.com>`, or you plus a `Co-authored-by`
  trailer (upstream CLA/DCO, design.md §2)?
- Does any test need the real docker daemon (privileged, host networking)? If yes: run that one as `bfleis`
  via sudo, deliberately.
