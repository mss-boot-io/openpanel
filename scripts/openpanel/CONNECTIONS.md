# OpenPanel VPS Connection Memory

Last updated: 2026-05-22 Asia/Shanghai

## Rules

- All SSH/SCP operations for these VPS nodes must be launched through WSL.
- Do not use Windows-native `ssh` or `scp` for deployment/debugging.
- Preferred local workspace:
  `/home/lwx/go/src/github.com/lwnmengjing/1Panel`
- Preferred Codex invocation pattern:
  `wsl -d Ubuntu --cd /home/lwx -e ssh ...`
- Preferred SSH options:
  `-o ConnectTimeout=12 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o IPQoS=none`

## Nodes

### Master

- IP: `216.152.152.236`
- User: `root`
- Port: `22`
- Role: master
- Codex WSL test status: OK
- Verified command:
  `wsl -d Ubuntu --cd /home/lwx -e ssh -o ConnectTimeout=12 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o IPQoS=none root@216.152.152.236 "hostname; uname -r; grep PRETTY_NAME /etc/os-release; id -u"`
- Verified output:
  - Hostname: `LAX-VPS-5-268825`
  - Kernel: `6.8.0-71-generic`
  - OS: `Ubuntu 24.04.3 LTS`
  - UID: `0`

### Worker 1

- IP: `169.197.142.252`
- User: `root`
- Port: `22`
- Role: worker
- Codex WSL test status: OK
- Verified command:
  `wsl -d Ubuntu --cd /home/lwx -e ssh -o ConnectTimeout=12 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o IPQoS=none root@169.197.142.252 "hostname; uname -r; grep PRETTY_NAME /etc/os-release; id -u"`
- Verified output:
  - Hostname: `SCL-VPS-4-267393`
  - Kernel: `6.8.0-117-generic`
  - OS: `Ubuntu 24.04.3 LTS`
  - UID: `0`

### Worker 2

- IP: `216.106.185.216`
- User: `root`
- Port: `22`
- Role: worker
- Codex WSL test status: OK
- Verified command:
  `wsl -d Ubuntu --cd /home/lwx -e ssh -o ConnectTimeout=12 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o IPQoS=none root@216.106.185.216 "hostname; uname -r; grep PRETTY_NAME /etc/os-release; id -u"`
- Verified output:
  - Hostname: `SCL-VPS-5-268826`
  - Kernel: `6.8.0-71-generic`
  - OS: `Ubuntu 24.04.3 LTS`
  - UID: `0`

## Deployment Target

- Master: `216.152.152.236`
- Workers:
  - `169.197.142.252`
  - `216.106.185.216`

Use the self-hosted scripts under `scripts/openpanel/`; do not use the upstream
online 1Panel installer.

## Current OpenPanel Deployment

- Verified at: `2026-05-22 14:xx Asia/Shanghai`
- Git origin: `git@github.com:mss-boot-io/openpanel.git`
- Git baseline: `8c4e325`, tag `openpanel-working-20260522`
- Git maintenance notes: `scripts/openpanel/GIT.md`
- Latest artifact deployed:
  `/home/lwx/go/src/github.com/lwnmengjing/1Panel/build/openpanel/openpanel-v2.0.0-open.20260522141626-linux-amd64.tar.gz`
- Master panel URL:
  `http://216.152.152.236:9999/openpanel`
- Service health after deploy:
  - `216.152.152.236`: `1panel-core=active`, `1panel-agent=active`
  - `169.197.142.252`: `1panel-core=active`, `1panel-agent=active`
  - `216.106.185.216`: `1panel-core=active`, `1panel-agent=active`
- Master local entrance check:
  `curl http://127.0.0.1:9999/openpanel` returned HTTP `200`.

## Current Open Nodes Mapping

- `local` -> `LAX-VPS-5-268825` (`216.152.152.236`)
- `open:1` -> `worker-169-197-142-252` -> `SCL-VPS-4-267393`
- `open:2` -> `worker-216-106-185-216` -> `SCL-VPS-5-268826`

Seed/update open nodes through:

```bash
wsl -d Ubuntu --cd /home/lwx/go/src/github.com/lwnmengjing/1Panel -e \
  scripts/openpanel/seed_open_nodes.sh ...
```

`seed_open_nodes.sh` is idempotent: it searches existing open nodes and updates
them instead of creating duplicates.

## Latest Verification Memory

- Browser-level E2E switching was verified with a temporary Playwright harness in
  `/tmp/openpanel-e2e`; this does not modify project dependencies.
- Verified switching sequence:
  `local -> open:1 -> open:2 -> local`.
- Dashboard hostnames observed in sequence:
  `LAX-VPS-5-268825 -> SCL-VPS-4-267393 -> SCL-VPS-5-268826 -> LAX-VPS-5-268825`.
- Relevant request headers observed:
  `CurrentNode=local`, `CurrentNode=open%3A1`, `CurrentNode=open%3A2`, then
  `CurrentNode=local`.
- No non-login-image `4xx` or `5xx` responses were observed during the final
  switching run.
- Screenshots from the final local E2E run:
  - `/tmp/openpanel-worker1-final.png`
  - `/tmp/openpanel-worker2-final.png`
  - `/tmp/openpanel-master-final.png`
