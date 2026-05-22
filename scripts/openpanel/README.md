# OpenPanel self-hosted deployment

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

- `build_artifact.sh` builds frontend assets plus Linux binaries and writes a
  tarball under `build/openpanel`.
- `install_node.sh` runs on a VPS from inside an extracted artifact and installs
  or updates one node.
- `deploy_cluster.sh` copies the artifact to one master and any number of
  worker nodes, then seeds the master's Open Nodes table through the master's
  API.

## Example

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
- `--reset-data` renames existing `/opt/1panel` data to a timestamped backup
  instead of deleting it.
