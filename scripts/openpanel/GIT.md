# OpenPanel Git Maintenance

Last updated: 2026-05-26 Asia/Shanghai

## Repository

- Local workspace: `/home/lwx/go/src/github.com/lwnmengjing/1Panel`
- Primary branch: `main`
- Origin: `git@github.com:mss-boot-io/openpanel.git`
- First baseline commit: `8c4e325 openpanel: initial custom working baseline`
- Baseline tag: `openpanel-working-20260522`
- Upstream source remote: `https://github.com/1Panel-dev/1Panel.git`

## Rules

- Push custom OpenPanel work to `origin`.
- Do not download upstream 1Panel binaries for deployed OpenPanel nodes.
- Keep the public OpenPanel one-click installer close to the official 1Panel
  quick-start flow; only the release/package source should point to OpenPanel.
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

Release tags:

- `openpanel-v2.0.0-open.1`
- points to `ab66895 openpanel: add installer and release workflow`
- CI failed because `frontend/src/views/container/image/build/index.vue` was
  ignored by the generic `build/` rule.
- `openpanel-v2.0.0-open.2`
- points to `ba1be5e openpanel: fix release build inputs`
- failed because `frontend/src/views/website/website/nginx/module/build` was
  also ignored by the generic `build/` rule.
- `openpanel-v2.0.0-open.3`
- points to `e740f66 openpanel: track frontend build source views`
- release succeeded and published assets.
- `openpanel-v2.0.0-open.4`
- points to `e68c5ca openpanel: keep public release installer only`
- succeeded with public-only release URLs.
- `openpanel-v2.0.0-open.5`
- points to `c88078a openpanel: align installer with upstream flow`
- current public release. It vendors official 1Panel installer files and ships
  official-style wrapped OpenPanel packages.

```bash
cd /home/lwx/go/src/github.com/lwnmengjing/1Panel
git tag openpanel-v2.0.0-open.N
git push origin openpanel-v2.0.0-open.N
```

GitHub CLI is installed and authenticated in WSL at `/home/lwx/.local/bin/gh`.
Use it for Actions and Release management.

The `.github/workflows/openpanel-release.yml` workflow uploads:

- `install.sh`
- `openpanel-linux-amd64.tar.gz`
- `openpanel-linux-arm64.tar.gz`
- versioned copies of the same artifacts
- `checksums.txt`

Release package layout:

- Top-level directory: `openpanel-<version>-linux-<arch>/`
- Official installer files at package root:
  `install.sh`, `1pctl`, `1panel-core`, `1panel-agent`, `initscript/`,
  `lang/`, `GeoIP.mmdb`.
- Extra local deployment compatibility files:
  `install_node.sh`, `usr/local/bin/*`, `etc/systemd/system/*`,
  `opt/openpanel/self/*`.

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
- `scripts/openpanel/installer/*`
- Root release installer `install.sh`
