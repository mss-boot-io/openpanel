#!/usr/bin/env bash
set -Eeuo pipefail

SSH_USER="root"
SSH_PORT="22"
MASTER_HOST=""
MASTER_API_KEY=""
PANEL_PORT="9999"
WORKERS=()
SSH_OPTS=(
  -o ConnectTimeout=12
  -o ConnectionAttempts=1
  -o StrictHostKeyChecking=accept-new
  -o IPQoS=none
)

usage() {
  cat <<'EOF_USAGE'
Usage: seed_open_nodes.sh --master HOST --master-api-key KEY --worker HOST:KEY [--worker HOST:KEY ...]

Options:
  --ssh-user root            SSH user.
  --ssh-port 22              SSH port.
  --port 9999                Master local panel port.
  --master HOST              Master host.
  --master-api-key KEY       API key enabled on the master.
  --worker HOST:KEY          Worker host and worker API key. Repeat as needed.
EOF_USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ssh-user) SSH_USER="$2"; shift 2 ;;
    --ssh-port) SSH_PORT="$2"; shift 2 ;;
    --port) PANEL_PORT="$2"; shift 2 ;;
    --master) MASTER_HOST="$2"; shift 2 ;;
    --master-api-key) MASTER_API_KEY="$2"; shift 2 ;;
    --worker) WORKERS+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [ -z "${MASTER_HOST}" ] || [ -z "${MASTER_API_KEY}" ] || [ "${#WORKERS[@]}" -eq 0 ]; then
  usage >&2
  exit 1
fi

remote_script() {
  cat <<'REMOTE'
set -Eeuo pipefail

md5_token() {
  local key="$1"
  local ts="$2"
  printf '1panel%s%s' "${key}" "${ts}" | md5sum | awk '{print $1}'
}

api_post() {
  local path="$1"
  local payload="$2"
  local ts token
  ts="$(date +%s)"
  token="$(md5_token "${MASTER_API_KEY}" "${ts}")"
  curl -fsS \
    --retry 20 \
    --retry-all-errors \
    --retry-delay 2 \
    -H "Content-Type: application/json" \
    -H "1Panel-Timestamp: ${ts}" \
    -H "1Panel-Token: ${token}" \
    -X POST \
    --data "${payload}" \
    "http://127.0.0.1:${PANEL_PORT}${path}"
}

json_payload() {
  local name="$1"
  local base_url="$2"
  local api_key="$3"
  local node_id="${4:-}"
  python3 - "$name" "$base_url" "$api_key" "$node_id" <<'PY'
import json
import sys

name, base_url, api_key, node_id = sys.argv[1:5]
payload = {
    "name": name,
    "baseUrl": base_url,
    "apiKey": api_key,
    "skipTLSVerify": True,
    "description": "seeded by scripts/openpanel/seed_open_nodes.sh",
}
if node_id:
    payload["id"] = int(node_id)
print(json.dumps(payload))
PY
}

find_node_id() {
  local name="$1"
  local payload response
  payload="$(python3 - "$name" <<'PY'
import json
import sys

print(json.dumps({"page": 1, "pageSize": 100, "info": sys.argv[1]}))
PY
)"
  response="$(api_post "/api/v2/core/open-nodes/search" "${payload}")"
  RESPONSE="${response}" python3 - "$name" <<'PY'
import json
import os
import sys

name = sys.argv[1]
response = json.loads(os.environ.get("RESPONSE", "{}"))
items = response.get("data", {}).get("items", []) or []
for item in items:
    if item.get("name") == name:
        print(item.get("id", ""))
        break
PY
}

post_node() {
  local name="$1"
  local base_url="$2"
  local api_key="$3"
  local node_id payload path
  node_id="$(find_node_id "${name}")"
  if [ -n "${node_id}" ]; then
    payload="$(json_payload "${name}" "${base_url}" "${api_key}" "${node_id}")"
    path="/api/v2/core/open-nodes/update"
  else
    payload="$(json_payload "${name}" "${base_url}" "${api_key}")"
    path="/api/v2/core/open-nodes"
  fi
  api_post "${path}" "${payload}"
}

while [ "$#" -gt 0 ]; do
  worker="$1"
  host="${worker%%:*}"
  api_key="${worker#*:}"
  name="worker-${host//./-}"
  post_node "${name}" "http://${host}:${PANEL_PORT}" "${api_key}"
  shift
done
REMOTE
}

for attempt in 1 2 3 4 5; do
  if remote_script | ssh -p "${SSH_PORT}" "${SSH_OPTS[@]}" "${SSH_USER}@${MASTER_HOST}" \
    "MASTER_API_KEY='${MASTER_API_KEY}' PANEL_PORT='${PANEL_PORT}' bash -s -- ${WORKERS[*]}"; then
    exit 0
  fi
  echo "seed attempt ${attempt} failed; retrying..." >&2
  sleep $((attempt * 2))
done

exit 1
