# OpenPanel self-hosted deployment

For a new conversation or a fresh agent session, start from the root memory
index first: `OPENPANEL_MEMORY.md`.

These scripts build and deploy this fork without downloading upstream 1Panel
binaries. OpenPanel's public release installer intentionally follows the
official 1Panel installer flow; the release package source is the only part
redirected to OpenPanel GitHub Releases.

The runtime paths intentionally stay compatible with the upstream codebase for
the first iteration:

- `/usr/local/bin/1panel-core`
- `/usr/local/bin/1panel-agent`
- `/usr/local/bin/1pctl`
- `/opt/1panel`
- `/etc/1panel/agent.sock`

That keeps the patch small because the application still contains hard-coded
compatibility paths. A later branding pass can rename paths and commands after
the node workflow is proven.

## Scripts

- `../../install.sh` is the public one-click installer. It mirrors the official
  1Panel quick-start flow and downloads OpenPanel release assets.
- `build_artifact.sh` builds frontend assets plus Linux binaries and writes an
  official-style installer tarball under `build/openpanel`.
- `install_node.sh` runs on a VPS from inside an extracted artifact and installs
  or updates one node.
- `upgrade_existing_node.sh` runs from the local WSL workspace and upgrades one
  existing 1Panel/OpenPanel node over SSH.
- `deploy_cluster.sh` copies the artifact to one master and any number of
  worker nodes, then seeds the master's Open Nodes table through the master's
  API.

## One-Click Install From Release

After an `openpanel-v*` Git tag has produced a GitHub Release, a fresh server can
install directly with:

```bash
curl -fsSL https://github.com/mss-boot-io/openpanel/releases/latest/download/install.sh | bash
```

The script downloads `openpanel-linux-<arch>.tar.gz`, verifies any cached local
package with the release checksum, extracts the official-style package, writes
`.selected_edition`, and then runs the package's installer. From that point on,
the prompts and installation behavior come from the official 1Panel installer
files vendored under `scripts/openpanel/installer/`.

```bash
OPENPANEL_RELEASE=openpanel-v2.0.0-open.5 \
  bash <(curl -fsSL https://github.com/mss-boot-io/openpanel/releases/latest/download/install.sh)
```

## Upgrade Existing 1Panel

For an existing open-source 1Panel installation, upgrade in place instead of
resetting data:

```bash
wsl -d Ubuntu --cd /home/lwx/go/src/github.com/lwnmengjing/1Panel -e \
  scripts/openpanel/upgrade_existing_node.sh \
  --host <server-ip> \
  --role master \
  --api-key <master-api-key>
```

The upgrade helper auto-detects the old installation base directory from
`/usr/local/bin/1pctl` when possible. This supports installations under `/opt`,
`/data`, `/www`, `/mnt/data`, `/home`, `/usr/local`, or a custom path supplied
with `--base-dir`.

By default, existing upgrades keep `<base-dir>/1panel/conf/app.yaml` and create
a root-only backup archive of `conf/` and `db/` under
`/root/openpanel-upgrade-backups`.

## Cluster Example

```bash
cd /home/lwx/go/src/github.com/lwnmengjing/1Panel

scripts/openpanel/deploy_cluster.sh \
  --master 216.152.152.236 \
  --worker 169.197.142.252 \
  --worker 216.106.185.216 \
  --reset-data
```

The script defaults to `root` SSH login, port `9999`, username `admin`, and a
random generated password/API keys. It prints the generated secrets at the end
and stores a root-only copy on each node at `/opt/1panel/conf/install-info`.

## Notes

- The public one-click installer should stay as close as possible to 1Panel's
  official `quick_start.sh`; only the release/binary source should point at
  OpenPanel.
- Release tarballs include the official 1Panel installer layout at package root
  and keep `install_node.sh` plus the legacy artifact layout only for the local
  WSL deployment helpers.
- The local WSL deployment helpers do not install Docker by default. The public
  one-click installer follows the official interactive Docker prompt.
- `--reset-data` renames existing `<base-dir>/1panel` data to a timestamped
  backup instead of deleting it.
