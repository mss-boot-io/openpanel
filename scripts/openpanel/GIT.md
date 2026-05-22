# OpenPanel Git Maintenance

Last updated: 2026-05-22 Asia/Shanghai

## Repository

- Local workspace: `/home/lwx/go/src/github.com/lwnmengjing/1Panel`
- Primary branch: `main`
- Origin: `git@github.com:mss-boot-io/openpanel.git`
- First baseline commit: `8c4e325 openpanel: initial custom working baseline`
- Baseline tag: `openpanel-working-20260522`
- Upstream source remote: `https://github.com/1Panel-dev/1Panel.git`

## Rules

- Push custom OpenPanel work to `origin`.
- Do not use upstream online install or online upgrade scripts for deployed
  nodes.
- Treat upstream 1Panel as source code only. Merge upstream changes locally,
  rebuild the custom artifact, then redeploy with `scripts/openpanel`.
- Keep generated outputs out of Git:
  - `build/`
  - `frontend/node_modules/`
  - `core/cmd/server/web/assets/`
  - `core/cmd/server/web/index.html`

## Normal Commit Flow

```bash
cd /home/lwx/go/src/github.com/lwnmengjing/1Panel
git status
git add <changed-files>
git commit -m "openpanel: describe the change"
git push origin main
```

## Release Flow

OpenPanel releases are published from tags named `openpanel-v*` so they do not
trigger the upstream `v*` release workflow.

Current first release tag:

- `openpanel-v2.0.0-open.1`
- points to `ab66895 openpanel: add installer and release workflow`

```bash
cd /home/lwx/go/src/github.com/lwnmengjing/1Panel
git tag openpanel-v2.0.0-open.1
git push origin openpanel-v2.0.0-open.1
```

The `.github/workflows/openpanel-release.yml` workflow uploads:

- `install.sh`
- `openpanel-linux-amd64.tar.gz`
- `openpanel-linux-arm64.tar.gz`
- versioned copies of the same artifacts
- `checksums.txt`

## Upstream Upgrade Flow

```bash
cd /home/lwx/go/src/github.com/lwnmengjing/1Panel
git fetch upstream --tags
git checkout -b upgrade/upstream-vX.Y.Z main
git merge upstream/vX.Y.Z
```

After resolving conflicts, rebuild and test:

```bash
scripts/openpanel/build_artifact.sh
scripts/openpanel/deploy_cluster.sh ...
```

The minimum acceptance test for every upstream merge is:

- Build succeeds.
- All three VPS services are active.
- Master entrance returns HTTP `200`.
- Open Nodes page lists both workers as healthy.
- Node switching succeeds in this order:
  `local -> open:1 -> open:2 -> local`.
- Dashboard hostnames observed:
  `LAX-VPS-5-268825 -> SCL-VPS-4-267393 -> SCL-VPS-5-268826 -> LAX-VPS-5-268825`.

## Custom Areas To Protect During Merges

- `core/app/model/open_node.go`
- `core/app/dto/open_node.go`
- `core/app/repo/open_node.go`
- `core/app/service/open_node.go`
- `core/app/api/v2/open_node.go`
- `core/router/ro_open_node.go`
- `core/router/common.go`
- `core/init/router/proxy.go`
- `core/init/migration/migrations/init.go`
- `core/app/auth/auth.go`
- `core/app/dto/auth.go`
- `frontend/src/api/interface/setting.ts`
- `frontend/src/api/modules/setting.ts`
- `frontend/src/utils/node.ts`
- `frontend/src/components/node-select/index.vue`
- `frontend/src/layout/components/Sidebar/components/Collapse.vue`
- `frontend/src/views/setting/open-node/index.vue`
- `scripts/openpanel/*`
