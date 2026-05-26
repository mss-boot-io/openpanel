#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

SSH_USER="root"
SSH_PORT="22"
MASTER_HOST=""
WORKER_HOSTS=()
ARTIFACT=""
PANEL_PORT="9999"
PANEL_USERNAME="admin"
PANEL_PASSWORD=""
PANEL_ENTRANCE="openpanel"
LANGUAGE="zh"
RESET_DATA="false"
SKIP_BUILD="false"
SKIP_APT="false"
MASTER_API_KEY=""
WORKER_API_KEYS=()
REMOTE_TMP="/tmp/openpanel-deploy"
SSH_OPTS=(
  -o ConnectTimeout=12
  -o ConnectionAttempts=1
  -o StrictHostKeyChecking=accept-new
  -o IPQoS=none
)

usage() {
  cat <<'EOF_USAGE'
Usage: deploy_cluster.sh --master HOST --worker HOST [--worker HOST ...] [options]

Options:
  --ssh-user root            SSH user.
  --ssh-port 22              SSH port.
  --artifact FILE            Use an existing artifact tarball.
  --skip-build               Require --artifact and do not build locally.
  --port 9999                Panel HTTP port.
  --username admin           Initial username for fresh nodes.
  --password VALUE           Initial password for fresh nodes.
  --entrance PATH            Initial security entrance.
  --language zh|en           Initial language.
  --master-api-key VALUE     API key enabled on the master.
  --worker-api-key VALUE     API key for the next worker; repeat per worker.
  --reset-data               Move existing /opt/1panel data aside on nodes.
  --skip-apt                 Do not install basic OS packages on nodes.
EOF_USAGE
}

random_alnum() {
  local length="${1:-32}"
  local value
  set +o pipefail
  value="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${length}")"
  set -o pipefail
  printf '%s' "${value}"
}

ssh_base() {
  ssh -p "${SSH_PORT}" "${SSH_OPTS[@]}" "$@"
}

scp_base() {
  scp -P "${SSH_PORT}" "${SSH_OPTS[@]}" "$@"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ssh-user) SSH_USER="$2"; shift 2 ;;
    --ssh-port) SSH_PORT="$2"; shift 2 ;;
    --master) MASTER_HOST="$2"; shift 2 ;;
    --worker) WORKER_HOSTS+=("$2"); shift 2 ;;
    --artifact) ARTIFACT="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD="true"; shift ;;
    --port) PANEL_PORT="$2"; shift 2 ;;
    --username) PANEL_USERNAME="$2"; shift 2 ;;
    --password) PANEL_PASSWORD="$2"; shift 2 ;;
    --entrance) PANEL_ENTRANCE="$2"; shift 2 ;;
    --language) LANGUAGE="$2"; shift 2 ;;
    --master-api-key) MASTER_API_KEY="$2"; shift 2 ;;
    --worker-api-key) WORKER_API_KEYS+=("$2"); shift 2 ;;
    --reset-data) RESET_DATA="true"; shift ;;
    --skip-apt) SKIP_APT="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [ -z "${MASTER_HOST}" ]; then
  echo "--master is required" >&2
  usage
  exit 1
fi
if [ "${#WORKER_HOSTS[@]}" -eq 0 ]; then
  echo "at least one --worker is required" >&2
  usage
  exit 1
fi
if [ -z "${PANEL_PASSWORD}" ]; then
  PANEL_PASSWORD="$(random_alnum 18)"
fi
if [ -z "${MASTER_API_KEY}" ]; then
  MASTER_API_KEY="$(random_alnum 32)"
fi
while [ "${#WORKER_API_KEYS[@]}" -lt "${#WORKER_HOSTS[@]}" ]; do
  WORKER_API_KEYS+=("$(random_alnum 32)")
done

build_artifact() {
  if [ -n "${ARTIFACT}" ]; then
    return
  fi
  if [ "${SKIP_BUILD}" = "true" ]; then
    echo "--skip-build requires --artifact" >&2
    exit 1
  fi
  ARTIFACT="$("${SCRIPT_DIR}/build_artifact.sh" | tail -n 1)"
}

install_remote() {
  local host="$1"
  local role="$2"
  local api_key="$3"
  local whitelist="$4"

  ssh_base "${SSH_USER}@${host}" "rm -rf '${REMOTE_TMP}' && mkdir -p '${REMOTE_TMP}'"
  scp_base "${ARTIFACT}" "${SSH_USER}@${host}:${REMOTE_TMP}/artifact.tar.gz"
  ssh_base "${SSH_USER}@${host}" "tar -xzf '${REMOTE_TMP}/artifact.tar.gz' -C '${REMOTE_TMP}'"
  local remote_work_dir
  remote_work_dir="$(ssh_base "${SSH_USER}@${host}" "set -e; if [ -f '${REMOTE_TMP}/install_node.sh' ]; then printf '%s\n' '${REMOTE_TMP}'; else find '${REMOTE_TMP}' -mindepth 1 -maxdepth 1 -type d | head -n 1; fi")"
  if [ -z "${remote_work_dir}" ]; then
    echo "failed to locate extracted OpenPanel package on ${host}" >&2
    exit 1
  fi

  local reset_arg=()
  local apt_arg=()
  if [ "${RESET_DATA}" = "true" ]; then
    reset_arg=(--reset-data)
  fi
  if [ "${SKIP_APT}" = "true" ]; then
    apt_arg=(--skip-apt)
  fi

  local remote_cmd=(
    bash "${remote_work_dir}/install_node.sh"
    --role "${role}"
    --port "${PANEL_PORT}"
    --username "${PANEL_USERNAME}"
    --password "${PANEL_PASSWORD}"
    --entrance "${PANEL_ENTRANCE}"
    --language "${LANGUAGE}"
    --api-key "${api_key}"
    --api-whitelist "${whitelist}"
    --api-validity 0
  )
  remote_cmd+=("${reset_arg[@]}" "${apt_arg[@]}")

  local quoted=""
  printf -v quoted '%q ' "${remote_cmd[@]}"
  ssh_base "${SSH_USER}@${host}" "${quoted}"
}

seed_open_nodes() {
  local args=(
    --ssh-user "${SSH_USER}"
    --ssh-port "${SSH_PORT}"
    --port "${PANEL_PORT}"
    --master "${MASTER_HOST}"
    --master-api-key "${MASTER_API_KEY}"
  )
  for i in "${!WORKER_HOSTS[@]}"; do
    args+=(--worker "${WORKER_HOSTS[$i]}:${WORKER_API_KEYS[$i]}")
  done
  "${SCRIPT_DIR}/seed_open_nodes.sh" "${args[@]}"
}

print_summary() {
  cat <<EOF_SUMMARY

Cluster deployment values
Master URL: http://${MASTER_HOST}:${PANEL_PORT}/${PANEL_ENTRANCE}
Username: ${PANEL_USERNAME}
Password: ${PANEL_PASSWORD}
Master API key: ${MASTER_API_KEY}
EOF_SUMMARY
  for i in "${!WORKER_HOSTS[@]}"; do
    echo "Worker ${WORKER_HOSTS[$i]} API key: ${WORKER_API_KEYS[$i]}"
  done
}

main() {
  build_artifact
  install_remote "${MASTER_HOST}" master "${MASTER_API_KEY}" "127.0.0.1"
  for i in "${!WORKER_HOSTS[@]}"; do
    install_remote "${WORKER_HOSTS[$i]}" worker "${WORKER_API_KEYS[$i]}" "${MASTER_HOST}"
  done
  seed_open_nodes
  print_summary
}

main "$@"
