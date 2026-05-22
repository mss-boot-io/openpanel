# OpenPanel self-hosted deployment

For a new conversation or a fresh agent session, start from the root memory
index first: `OPENPANEL_MEMORY.md`.

These scripts deploy this fork without using the upstream 1Panel online
installer. They build local artifacts from the current workspace, copy them to
Ubuntu nodes over SSH, install systemd services, and optionally seed Open Nodes
through the public API.

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

- `../../install.sh` is the one-click server-side installer. It downloads a
  GitHub Release artifact and installs or upgrades the current node.
- `build_artifact.sh` builds frontend assets plus Linux binaries and writes a
  tarball under `build/openpanel`.
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
curl -fsSL https://github.com/mss-boot-io/openpanel/releases/latest/download/install.sh | \
  bash -s -- --role master --port 9999 --entrance openpanel
```

For a worker node that should accept Open Nodes calls from a master:

```bash
curl -fsSL https://github.com/mss-boot-io/openpanel/releases/latest/download/install.sh | \
  bash -s -- --role worker --api-key <worker-api-key> --api-whitelist <master-ip>
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

- This is not the upstream installer and does not download upstream 1Panel
  install scripts.
- Docker is not installed by default. Install Docker separately if you want to
  test app/container workflows.
- `--reset-data` renames existing `<base-dir>/1panel` data to a timestamped
  backup instead of deleting it.
