# atc-box-1: proposed runbook after REVIEW-PERIMETER (MIGRATION, 2026-11-06)

**Status: proposal. Nothing here has run.** Each AWS command runs only on the owner's OK in the MIGRATION
session, after it is shown. Run from OLD (the Midway machine) as `bfleis`, zsh: `P=(--profile dev-admin --region
eu-west-1)`. Documents: `~/.local/state/migration/iam/proposed/` (host-private master; the copies in
[../iam/proposed/](../iam/proposed/) are for reading only, never `file://` them on the host). All documents pass
Access Analyzer `validate-policy` with 0 findings (with a test IP in place of `__EIP__`).

Source: [REVIEW-PERIMETER report](../../../reviews/2026-11-06/REVIEW-PERIMETER/report.md) (must-fix M1-M4,
should-fix S*). Owner questions Q1-Q10 are `Perimeter: …` entries in `dev-env/TODO.md`.

Found already in place (read-only, 2026-11-06): the Isengard CloudTrail trail `IsengardTrail-DO-NOT-DELETE`
(multi-region, all management events, Isengard-owned bucket), so Bedrock invokes are logged already (M4 part).
GuardDuty detector enabled in eu-west-1 (publishing every 6 h). Not in place: EBS encryption by default, the
account IMDS defaults, budgets, SNS topics, alert rules, VPC endpoints (none, so the `aws:SourceIp` pin is safe
as written).

## A. Before launch (account-level, no box yet)

```sh
cd ~/.local/state/migration/iam/proposed
# A1 (S) EBS encryption by default; account IMDS default v2-only, hop 1
aws $P ec2 enable-ebs-encryption-by-default
aws $P ec2 modify-instance-metadata-defaults --http-tokens required --http-put-response-hop-limit 1
# A2 (M3) Session Manager-only policy instead of AmazonSSMManagedInstanceCore (no box yet, so no session to break)
aws $P iam create-policy --policy-name ssm-session-only --policy-document file://ssm-session-only.json --tags Key=project,Value=atc
aws $P iam attach-role-policy --role-name atc-box --policy-arn arn:aws:iam::655495220320:policy/ssm-session-only
aws $P iam detach-role-policy --role-name atc-box --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws $P logs create-log-group --log-group-name /atc/ssm --tags project=atc
aws $P logs put-retention-policy --log-group-name /atc/ssm --retention-in-days 30
# A3 bedrock-invoke v3 (owner: all models): any profile/foundation model in any region, bedrock-mantle:* (OpenAI);
#    narrow bedrock-mantle:* to the actions CloudTrail shows after a week
aws $P iam create-policy-version --policy-arn arn:aws:iam::655495220320:policy/bedrock-invoke \
  --policy-document file://bedrock-invoke.v3.json --set-as-default
# A4 (S) capability ceilings
aws $P iam put-role-policy --role-name atc-box       --policy-name reviewed-ceiling --policy-document file://atc-ceiling.json
aws $P iam put-role-policy --role-name agent-bedrock --policy-name reviewed-ceiling --policy-document file://agent-ceiling.json
# A5 (M4) alerts: SNS to the owner (confirm the mail), GuardDuty findings + AccessDenied by the two roles
aws $P sns create-topic --name atc-alerts --tags Key=project,Value=atc
aws $P sns subscribe --topic-arn arn:aws:sns:eu-west-1:655495220320:atc-alerts --protocol email --notification-endpoint <owner mail>
aws $P guardduty update-detector --detector-id 84d09d19adc30f93c97564f6032ce3c9 --finding-publishing-frequency FIFTEEN_MINUTES
#   EventBridge rules (patterns in fable §5.7 / astra §5); TODO before running: verify that read-only
#   CloudTrail events (InvokeModel) reach EventBridge only with state ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS (M).
# A6 budget alert only (owner: no ceiling/action for now). Amount is a tripwire, not a cap; change it freely.
aws --profile dev-admin budgets create-budget --account-id 655495220320 \
  --budget '{"BudgetName":"atc-monthly","BudgetLimit":{"Amount":"<USD>","Unit":"USD"},"TimeUnit":"MONTHLY","BudgetType":"COST"}' \
  --notifications-with-subscribers '[{"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":80,"ThresholdType":"PERCENTAGE"},"Subscribers":[{"SubscriptionType":"EMAIL","Address":"<owner mail>"}]},{"Notification":{"NotificationType":"FORECASTED","ComparisonOperator":"GREATER_THAN","Threshold":100,"ThresholdType":"PERCENTAGE"},"Subscribers":[{"SubscriptionType":"EMAIL","Address":"<owner mail>"}]}]'
```

## B. Launch

```sh
SG=$(aws $P ec2 create-security-group --group-name atc-box --description 'atc box: no inbound, SSM only' \
  --vpc-id vpc-0177bc81692630656 --tag-specifications 'ResourceType=security-group,Tags=[{Key=project,Value=atc}]' \
  --query GroupId --output text)
aws $P ec2 run-instances --image-id ami-00fcaf85b81e85b1d --instance-type m7i.4xlarge \
  --subnet-id subnet-086daee468c4cba4c --security-group-ids $SG --iam-instance-profile Name=atc-box \
  --metadata-options HttpEndpoint=enabled,HttpTokens=required,HttpPutResponseHopLimit=1 \
  --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=600,VolumeType=gp3,Iops=6000,Throughput=500,Encrypted=true,DeleteOnTermination=false}' \
  --disable-api-termination --instance-initiated-shutdown-behavior stop \
  --user-data file://$HOME/.local/state/migration/ec2/user-data.v2.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=atc-box-1},{Key=project,Value=atc}]' 'ResourceType=volume,Tags=[{Key=project,Value=atc}]' \
  --query 'Instances[0].InstanceId' --output text
```

Owner ssh + mosh inbound (owner, 2026-11-06: fixed places, VPN otherwise), after the launch:

```sh
for c in 54.240.197.235/32 <home>/32; do   # work, as AWS sees it (checkip.amazonaws.com, 2026-11-06); home TBD
  aws $P ec2 authorize-security-group-ingress --group-id $SG --ip-permissions \
    "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=$c,Description=owner-ssh}]" \
    "IpProtocol=udp,FromPort=60000,ToPort=60010,IpRanges=[{CidrIp=$c,Description=owner-mosh}]"
done
```

At work the source AWS sees is the Amazon corp egress `54.240.197.235`, not the `<work-ip>` that
non-AWS sites show (split routing). If it changes between sessions, widen to `54.240.197.0/24`. Confirm the
real source in the box's sshd log on the first login. No `0.0.0.0/0`, ever: an agent can write `~/.ssh/authorized_keys`. user-data then also needs mosh, the
owner's own public key (a second `authorized_keys` line without the `rrsync` restriction) and
`/etc/ssh/sshd_config.d/90-atc.conf` (`PasswordAuthentication no`, `KbdInteractiveAuthentication no`,
`AllowUsers bfleis`).

No `--key-name` (S, A12). `user-data.v2.sh`: no `|| true`, no mosh, no `agent` user/iptables, `ForwardAgent
no`, the cutover key forced to write-only `rrsync` into `/opt`. Before launch, `__PUBKEY__` is replaced with
OLD's new `~/.ssh/id_ed25519_atcbox.pub` (that key stays on OLD; M2).

## C. Right after launch: pin (M1)

```sh
EIP=$(aws $P ec2 allocate-address --domain vpc --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=atc-box-1},{Key=project,Value=atc}]' --query AllocationId --output text)
aws $P ec2 associate-address --instance-id <i-…> --allocation-id $EIP
IP=$(aws $P ec2 describe-addresses --allocation-ids $EIP --query 'Addresses[0].PublicIp' --output text)
sed "s/__EIP__/$IP/" pin-to-box.json > pin-to-box.live.json; sed "s/__EIP__/$IP/" agent-bedrock-trust.v2.json > agent-bedrock-trust.live.json
aws $P iam put-role-policy --role-name atc-box       --policy-name pin-to-box --policy-document file://pin-to-box.live.json
aws $P iam put-role-policy --role-name agent-bedrock --policy-name pin-to-box --policy-document file://pin-to-box.live.json
aws $P iam update-assume-role-policy --role-name agent-bedrock --policy-document file://agent-bedrock-trust.live.json
```

Drill once: from the box, `converse` with `eu.anthropic.claude-opus-5-5` succeeds; a `us.`/`global.` profile is
denied (unless Q1); a copy of the box credentials used on OLD gets `AccessDenied` and an alert. Lock-out
recovery: `aws $P iam delete-role-policy --role-name atc-box --policy-name pin-to-box` from OLD.

## D. Kill switch (keep on OLD / the owner's machine, never on the box)

```sh
for r in atc-box agent-bedrock; do aws $P iam put-role-policy --role-name $r --policy-name KILL --policy-document file://KILL.json; done
aws $P ec2 create-snapshot --volume-id <vol-…> --description 'atc-box-1 incident'   # optional
aws $P ec2 stop-instances --instance-ids <i-…>                                         # hostile guest: --force
# then: revoke GitHub tokens/keys (Q2) and the git.int.fleis.net key (Q9).
# undo: delete-role-policy --policy-name KILL on both roles; start-instances.
```

## E. Owner-level secrets: rules for the cutover (M2)

- On the box: no `gh auth login` as the owner, no personal ssh key, no key into OLD, no ada/Midway,
  `ForwardAgent no`.
- The home export is an allowlist, not the cutover plan §0.4 tarball: herdr/pi/zsh config without credentials.
  Not: `.codex/auth.json`, `.claude/.credentials.json`, `~/.aws/*` (cache, config), `env-local.zsh` (old
  GH_TOKEN), `.ssh/*`.
- New secrets made on the box are agent-readable by design and get scoped accordingly: GitHub (Q2, Q3),
  `git.int.fleis.net` repo-only key (Q9).
- After the cutover: remove the `rrsync` line from `authorized_keys` and the key on OLD.

## F. After the cutover (owner decision 2026-11-06)

1. **Secret audit** (MIGRATION): scan OLD and NEW (`/opt/workspace`, `~`, pi/Codex/Claude session logs, nvim
   undo, shell snapshots, history) for GitHub tokens (`ghp_`, `github_pat_`), AWS keys, other credentials;
   list every copy by path, values never printed.
2. **Rotate the GitHub tokens** (owner), after the audit: both PATs in `~/.local/state/zsh/env-local.zsh`
   on OLD. Owner: "these are all RO tokens right now, so the risk is minimal" — so they stay in place until
   the transition is done. Known exposures: the fine-grained `GH_TOKEN` (`github_pat_…`, expires 2027-10-16,
   live) was printed in full into the MIGRATION session on 2026-11-06; the classic `ghp_…Sdh` (commented out)
   already answers 401. Then the new box gets its own scoped tokens (atc-tasks push, forks).
3. **Clean up** the copies the audit found (incl. the MIGRATION session log), then close
   `dev-env/2026-10-15: Rotate the GH_TOKEN…`.
4. Remove the OLD rules from SG `sg-088b864198c65e7e9` (tcp 22 from 54.240.197.227/32 and .235/32) and the
   `rrsync` line from `~/.ssh/authorized_keys` on NEW; delete `~/.ssh/id_ed25519_atcbox` on OLD.
