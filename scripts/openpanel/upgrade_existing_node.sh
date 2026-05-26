#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SSH_USER="root"
SSH_PORT="22"
HOST=""
ROLE="master"
BASE_DIR=""
ARTIFACT=""
SKIP_BUILD="false"
API_KEY=""
API_WHITELIST=""
API_VALIDITY="0"
BACKUP_MODE="core"
RESET_DATA="false"
SKIP_APT="true"
REMOTE_TMP="/tmp/openpanel-upgrade"
SSH_OPTS=(
  -o ConnectTimeout=12
  -o ConnectionAttempts=1
  -o StrictHostKeyChecking=accept-new
  -o IPQoS=none
)

usage() {
  cat <<'EOF_USAGE'
Usage: upgrade_existing_node.sh --host HOST [options]

This script upgrades one existing 1Panel/OpenPanel node in place. It preserves
the current data directory by default and auto-detects non-/opt install bases
from /usr/local/bin/1pctl when possible.

Options:
  --host HOST                Target server.
  --ssh-user root            SSH user.
  --ssh-port 22              SSH port.
  --role master|worker       Node role label. Default: master.
  --base-dir DIR             Existing install base dir. Auto-detected.
  --artifact FILE            Use an existing artifact tarball.
  --skip-build               Require --artifact and do not build locally.
  --api-key VALUE            Enable public API with this key.
  --api-whitelist VALUE      Newline or comma separated API whitelist.
  --api-validity MINUTES     API timestamp validity. 0 disables expiry.
  --backup-mode core|full|none
                             core backs up conf/ and db/. Default: core.
  --reset-data               Move existing <base-dir>/1panel aside first.
  --with-apt                 Allow install_node.sh to install base packages.
  -h, --help                 Show this help.
EOF_USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

ssh_base() {
  ssh -p "${SSH_PORT}" "${SSH_OPTS[@]}" "$@"
}

scp_base() {
  scp -P "${SSH_PORT}" "${SSH_OPTS[@]}" "$@"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --ssh-user) SSH_USER="$2"; shift 2 ;;
    --ssh-port) SSH_PORT="$2"; shift 2 ;;
    --role) ROLE="$2"; shift 2 ;;
    --base-dir) BASE_DIR="$2"; shift 2 ;;
    --artifact) ARTIFACT="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD="true"; shift ;;
    --api-key) API_KEY="$2"; shift 2 ;;
    --api-whitelist) API_WHITELIST="$2"; shift 2 ;;
    --api-validity) API_VALIDITY="$2"; shift 2 ;;
    --backup-mode) BACKUP_MODE="$2"; shift 2 ;;
    --reset-data) RESET_DATA="true"; shift ;;
    --with-apt) SKIP_APT="false"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[ -n "${HOST}" ] || { usage; exit 1; }
if [ "${ROLE}" != "master" ] && [ "${ROLE}" != "worker" ]; then
  die "--role must be master or worker"
fi
if [ "${BACKUP_MODE}" != "core" ] && [ "${BACKUP_MODE}" != "full" ] && [ "${BACKUP_MODE}" != "none" ]; then
  die "--backup-mode must be core, full, or none"
fi

if [ -z "${ARTIFACT}" ]; then
  if [ "${SKIP_BUILD}" = "true" ]; then
    die "--skip-build requires --artifact"
  fi
  ARTIFACT="$("${SCRIPT_DIR}/build_artifact.sh" | tail -n 1)"
fi
[ -f "${ARTIFACT}" ] || die "artifact not found: ${ARTIFACT}"

detect_remote_base_dir() {
  if [ -n "${BASE_DIR}" ]; then
    printf '%s\n' "${BASE_DIR%/}"
    return
  fi
  ssh_base "${SSH_USER}@${HOST}" 'set -e
if [ -r /usr/local/bin/1pctl ]; then
  value="$(sed -n -E "s/^BASE_DIR=(.*)$/\1/p" /usr/local/bin/1pctl | head -n 1 | sed -E "s/^['\''\"]//; s/['\''\"]$//")"
  if [ -n "$value" ] && [ -d "${value%/}/1panel" ]; then
    printf "%s\n" "${value%/}"
    exit 0
  fi
fi
for candidate in /opt /data /www /mnt/data /home /usr/local; do
  if [ -s "${candidate%/}/1panel/conf/app.yaml" ]; then
    printf "%s\n" "${candidate%/}"
    exit 0
  fi
done
printf "/opt\n"'
}

REMOTE_BASE_DIR="$(detect_remote_base_dir)"

backup_remote() {
  if [ "${RESET_DATA}" = "true" ] || [ "${BACKUP_MODE}" = "none" ]; then
    return
  fi
  ssh_base "${SSH_USER}@${HOST}" \
    "BASE_DIR=$(printf '%q' "${REMOTE_BASE_DIR}") BACKUP_MODE=$(printf '%q' "${BACKUP_MODE}") bash -s" <<'EOF_REMOTE'
set -Eeuo pipefail
data_dir="${BASE_DIR%/}/1panel"
[ -d "${data_dir}" ] || exit 0
ts="$(date +%Y%m%d%H%M%S)"
backup_dir="/root/openpanel-upgrade-backups"
mkdir -p "${backup_dir}"
backup_file="${backup_dir}/$(hostname)-${ts}-${BACKUP_MODE}.tar.gz"
case "${BACKUP_MODE}" in
  core)
    items=()
    [ -e "${data_dir}/conf" ] && items+=(conf)
    [ -e "${data_dir}/db" ] && items+=(db)
    [ "${#items[@]}" -gt 0 ] || exit 0
    tar -C "${data_dir}" -czf "${backup_file}" "${items[@]}"
    ;;
  full)
    tar -C "${BASE_DIR%/}" -czf "${backup_file}" 1panel
    ;;
esac
chmod 0600 "${backup_file}"
echo "backup: ${backup_file}"
EOF_REMOTE
}

install_remote() {
  ssh_base "${SSH_USER}@${HOST}" "rm -rf '${REMOTE_TMP}' && mkdir -p '${REMOTE_TMP}'"
  scp_base "${ARTIFACT}" "${SSH_USER}@${HOST}:${REMOTE_TMP}/artifact.tar.gz"
  ssh_base "${SSH_USER}@${HOST}" "tar -xzf '${REMOTE_TMP}/artifact.tar.gz' -C '${REMOTE_TMP}'"
  local remote_work_dir
  remote_work_dir="$(ssh_base "${SSH_USER}@${HOST}" "set -e; if [ -f '${REMOTE_TMP}/install_node.sh' ]; then printf '%s\n' '${REMOTE_TMP}'; else find '${REMOTE_TMP}' -mindepth 1 -maxdepth 1 -type d | head -n 1; fi")"
  if [ -z "${remote_work_dir}" ]; then
    die "failed to locate extracted OpenPanel package on ${HOST}"
  fi

  local args=(
    bash "${remote_work_dir}/install_node.sh"
    --role "${ROLE}"
    --base-dir "${REMOTE_BASE_DIR}"
    --api-validity "${API_VALIDITY}"
  )
  [ -n "${API_KEY}" ] && args+=(--api-key "${API_KEY}")
  if [ -n "${API_KEY}" ] && [ -z "${API_WHITELIST}" ]; then
    API_WHITELIST="127.0.0.1"
  fi
  [ -n "${API_WHITELIST}" ] && args+=(--api-whitelist "${API_WHITELIST}")
  [ "${RESET_DATA}" = "true" ] && args+=(--reset-data)
  [ "${RESET_DATA}" != "true" ] && args+=(--preserve-config)
  [ "${SKIP_APT}" = "true" ] && args+=(--skip-apt)

  local quoted=""
  printf -v quoted '%q ' "${args[@]}"
  ssh_base "${SSH_USER}@${HOST}" "${quoted}"
}

print_status() {
  ssh_base "${SSH_USER}@${HOST}" \
    "systemctl is-active 1panel-core.service 1panel-agent.service; /usr/local/bin/1pctl user-info"
}

echo "target: ${HOST}"
echo "base dir: ${REMOTE_BASE_DIR}"
echo "artifact: ${ARTIFACT}"
backup_remote
install_remote
print_status
