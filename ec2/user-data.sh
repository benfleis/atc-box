#!/bin/bash
# atc-box-1 first boot (cloud-init), v2 after REVIEW-PERIMETER. No secrets in here (user-data is readable
# from IMDS by every process on the box). Same uid/gid as OLD, so rsync --numeric-ids carries ownership.
set -euxo pipefail
hostnamectl set-hostname atc-box-1
dnf install -y git zsh tmux rsync jq lua glibc-langpack-en zstd docker gcc gcc-c++ make cmake ninja-build openssl-devel perl python3
# AL2023 has no mosh package (mosh-server comes from bfleis's mise, as on OLD) and ships rrsync only as a doc file.
install -m 755 /usr/share/doc/rsync/support/rrsync /usr/local/bin/rrsync
groupadd -g 10100 amazon
useradd -u 35914290 -g 10100 -m -s /bin/zsh bfleis
chmod 700 /home/bfleis
# Q4 (root-equivalent box accepted?): docker group + NOPASSWD sudo make every agent root. Kept pending the answer.
usermod -aG docker bfleis
echo 'bfleis ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-bfleis && chmod 440 /etc/sudoers.d/90-bfleis
# Line 1 of authorized_keys: the owner's key (private half on his own machine).
# Cutover only: OLD pushes into /opt (workspace + /opt/migration-in for the allowlisted home export) over
# SSH-over-SSM. The key is OLD's; NEW holds no key into OLD. Forced rrsync, write-only; remove after cutover.
install -d -o bfleis -g 10100 -m 700 /home/bfleis/.ssh /opt/migration-in
command -v rrsync || { echo "rrsync missing: install it or change the forced command" >&2; exit 1; }
cat > /home/bfleis/.ssh/authorized_keys <<'K'
__OWNER_PUBKEY__
restrict,command="rrsync -wo /opt" __CUTOVER_PUBKEY__
K
chown bfleis:10100 /home/bfleis/.ssh/authorized_keys && chmod 600 /home/bfleis/.ssh/authorized_keys
# Owner ssh/mosh inbound (SG restricts the source IPs); keys only.
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\nAllowUsers bfleis\nAllowAgentForwarding no\n' > /etc/ssh/sshd_config.d/90-atc.conf
sshd -t && systemctl reload sshd
printf 'Host *\n  ForwardAgent no\n  IdentitiesOnly yes\n' > /etc/ssh/ssh_config.d/90-atc.conf
install -d -o bfleis -g 10100 -m 755 /opt/workspace
install -d -o root -g root -m 755 /opt/tooling
systemctl enable --now docker
