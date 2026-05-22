# OpenPanel Memory Index

Last updated: 2026-05-22 Asia/Shanghai

This file is the first place to read in a new Codex conversation. It indexes
the project memory needed to continue development, deployment, and upstream
upgrade work without rediscovering the setup.

## Start Here

1. Read this file.
2. Read `scripts/openpanel/CONNECTIONS.md`.
3. Read `scripts/openpanel/GIT.md`.
4. Read `scripts/openpanel/README.md`.

## High-Level Project State

- This workspace is a self-developed OpenPanel fork based on the open-source
  1Panel codebase.
- The custom goal is not to bypass licensing; it adds an independent Open Nodes
  path that lets a master panel manage other self-hosted 1Panel/OpenPanel nodes
  through their public API keys.
- The deployed cluster is currently functional and verified:
  `local -> open:1 -> open:2 -> local`.
- The upstream online installer and online upgrade flow must not be used for
  this fork. Build and deploy with `scripts/openpanel/*`.

## Most Important Memory Files

- `scripts/openpanel/CONNECTIONS.md`
  - VPS node inventory.
  - WSL-only SSH rule.
  - Current deployment artifact.
  - Open Nodes mapping.
  - Latest browser/E2E verification notes.
- `scripts/openpanel/GIT.md`
  - Git remotes.
  - Baseline commit and tag.
  - Upstream merge workflow.
  - Files to protect during official 1Panel updates.
- `scripts/openpanel/README.md`
  - Self-hosted build/deploy script usage.
  - Runtime paths and deployment notes.

## Git Memory

- Origin: `git@github.com:mss-boot-io/openpanel.git`
- Primary branch: `main`
- Upstream source: `https://github.com/1Panel-dev/1Panel.git`
- Baseline tag: `openpanel-working-20260522`
- Baseline commit: `8c4e325 openpanel: initial custom working baseline`

## Deployment Memory

- Master: `216.152.152.236`
- Worker 1: `169.197.142.252`
- Worker 2: `216.106.185.216`
- SSH rule: always connect from WSL, for example:

```bash
wsl -d Ubuntu --cd /home/lwx -e ssh root@216.152.152.236
```

Do not use Windows-native `ssh` or `scp` for these nodes.

## Current Node Mapping

- `local` -> `LAX-VPS-5-268825` (`216.152.152.236`)
- `open:1` -> `worker-169-197-142-252` -> `SCL-VPS-4-267393`
- `open:2` -> `worker-216-106-185-216` -> `SCL-VPS-5-268826`

## Secret Handling

Do not commit panel passwords or API keys to Git. Runtime install secrets live
on the servers under `/opt/1panel/conf/install-info` and can be inspected over
WSL SSH when needed.

## Custom Feature Areas

When continuing work or merging upstream 1Panel updates, inspect these areas
first:

- Backend Open Nodes model, DTO, repo, service, API, router.
- `core/init/router/proxy.go` open-node proxy split.
- Auth current-user compatibility in `core/app/auth/auth.go` and
  `core/app/dto/auth.go`.
- Frontend node list/selector logic in `frontend/src/utils/node.ts` and
  `frontend/src/layout/components/Sidebar/components/Collapse.vue`.
- Open Nodes settings page under `frontend/src/views/setting/open-node`.
- Self-hosted scripts under `scripts/openpanel`.

## Minimum Acceptance Test

After any important change or upstream merge:

- Build succeeds with `scripts/openpanel/build_artifact.sh`.
- Deploy succeeds with `scripts/openpanel/deploy_cluster.sh`.
- All three nodes report `1panel-core=active` and `1panel-agent=active`.
- Master entrance returns HTTP `200`.
- Open Nodes page shows both workers healthy.
- Dashboard switching works:
  `local -> open:1 -> open:2 -> local`.
- Observed dashboard hostnames:
  `LAX-VPS-5-268825 -> SCL-VPS-4-267393 -> SCL-VPS-5-268826 -> LAX-VPS-5-268825`.

## Search Keywords

Use these keywords when looking for memory:

- `OpenPanel Memory Index`
- `OpenPanel VPS Connection Memory`
- `OpenPanel Git Maintenance`
- `openpanel-working-20260522`
- `open:1`
- `open:2`
- `WSL-only SSH`
- `self-hosted deployment`
