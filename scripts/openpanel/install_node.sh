#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROLE="worker"
BASE_DIR="/opt"
PANEL_PORT="9999"
PANEL_USERNAME="admin"
PANEL_PASSWORD=""
PANEL_ENTRANCE="openpanel"
LANGUAGE="zh"
VERSION=""
API_KEY=""
API_WHITELIST="127.0.0.1"
API_VALIDITY="0"
RESET_DATA="false"
SKIP_APT="false"
PRESERVE_CONFIG="false"

BASE_DIR_SET="false"
PANEL_PORT_SET="false"
PANEL_USERNAME_SET="false"
PANEL_PASSWORD_SET="false"
PANEL_ENTRANCE_SET="false"
LANGUAGE_SET="false"

usage() {
  cat <<'EOF_USAGE'
Usage: install_node.sh [options]

Options:
  --role master|worker       Node role label for install metadata.
  --base-dir /opt            Runtime base dir used by the app. Auto-detected
                             from an existing 1pctl when omitted.
  --port 9999                Core HTTP listen port.
  --username admin           Initial panel username for a new database.
  --password VALUE           Initial panel password for a new database.
  --entrance PATH            Initial security entrance for a new database.
  --language zh|en           Initial language.
  --version VALUE            Version label stored in 1pctl/app config.
  --api-key VALUE            Enable the public API with this key after init.
  --api-whitelist VALUE      Newline or comma separated API IP whitelist.
  --api-validity MINUTES     API timestamp validity. 0 disables expiry.
  --reset-data               Move existing <base-dir>/1panel data aside first.
  --skip-apt                 Do not install basic OS packages.
  --preserve-config          Keep an existing <base-dir>/1panel/conf/app.yaml.
EOF_USAGE
}

random_alnum() {
  local length="${1:-24}"
  local value
  set +o pipefail
  value="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${length}")"
  set -o pipefail
  printf '%s' "${value}"
}

normalize_list() {
  printf '%s' "$1" | tr ',' '\n' | sed '/^[[:space:]]*$/d'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --role) ROLE="$2"; shift 2 ;;
    --base-dir) BASE_DIR="$2"; BASE_DIR_SET="true"; shift 2 ;;
    --port) PANEL_PORT="$2"; PANEL_PORT_SET="true"; shift 2 ;;
    --username) PANEL_USERNAME="$2"; PANEL_USERNAME_SET="true"; shift 2 ;;
    --password) PANEL_PASSWORD="$2"; PANEL_PASSWORD_SET="true"; shift 2 ;;
    --entrance) PANEL_ENTRANCE="$2"; PANEL_ENTRANCE_SET="true"; shift 2 ;;
    --language) LANGUAGE="$2"; LANGUAGE_SET="true"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --api-key) API_KEY="$2"; shift 2 ;;
    --api-whitelist) API_WHITELIST="$2"; shift 2 ;;
    --api-validity) API_VALIDITY="$2"; shift 2 ;;
    --reset-data) RESET_DATA="true"; shift ;;
    --skip-apt) SKIP_APT="true"; shift ;;
    --preserve-config) PRESERVE_CONFIG="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [ "$(id -u)" != "0" ]; then
  echo "install_node.sh must run as root" >&2
  exit 1
fi

if [ "${ROLE}" != "master" ] && [ "${ROLE}" != "worker" ]; then
  echo "--role must be master or worker" >&2
  exit 1
fi

yaml_value() {
  local key="$1"
  local file="$2"
  sed -n -E "s/^[[:space:]]*${key}:[[:space:]]*['\"]?([^'\"]*)['\"]?[[:space:]]*$/\1/p" "${file}" | head -n 1
}

ctl_value() {
  local key="$1"
  local file="${2:-/usr/local/bin/1pctl}"
  [ -r "${file}" ] || return 0
  sed -n -E "s/^${key}=(.*)$/\1/p" "${file}" | head -n 1 | sed -E "s/^['\"]//; s/['\"]$//"
}

detect_existing_base_dir() {
  local value candidate

  if [ "${BASE_DIR_SET}" = "true" ] || [ "${RESET_DATA}" = "true" ]; then
    return
  fi

  value="$(ctl_value BASE_DIR)"
  if [ -n "${value}" ] && [ -d "${value%/}/1panel" ]; then
    BASE_DIR="${value%/}"
    return
  fi

  for candidate in /opt /data /www /mnt/data /home /usr/local; do
    if [ -s "${candidate%/}/1panel/conf/app.yaml" ]; then
      BASE_DIR="${candidate%/}"
      return
    fi
  done
}

load_preserved_config_values() {
  local app_yaml="${BASE_DIR%/}/1panel/conf/app.yaml"
  local value

  if [ "${PRESERVE_CONFIG}" != "true" ] || [ "${RESET_DATA}" = "true" ] || [ ! -s "${app_yaml}" ]; then
    return
  fi

  if [ "${PANEL_PORT_SET}" != "true" ]; then
    value="$(yaml_value port "${app_yaml}")"
    [ -n "${value}" ] && PANEL_PORT="${value}"
  fi
  if [ "${PANEL_USERNAME_SET}" != "true" ]; then
    value="$(yaml_value username "${app_yaml}")"
    [ -n "${value}" ] && PANEL_USERNAME="${value}"
  fi
  if [ "${PANEL_PASSWORD_SET}" != "true" ]; then
    value="$(yaml_value password "${app_yaml}")"
    [ -n "${value}" ] && PANEL_PASSWORD="${value}"
  fi
  if [ "${PANEL_ENTRANCE_SET}" != "true" ]; then
    value="$(yaml_value entrance "${app_yaml}")"
    [ -n "${value}" ] && PANEL_ENTRANCE="${value}"
  fi
  if [ "${LANGUAGE_SET}" != "true" ]; then
    value="$(yaml_value language "${app_yaml}")"
    [ -n "${value}" ] && LANGUAGE="${value}"
  fi
}

detect_existing_base_dir
load_preserved_config_values

if [ -z "${PANEL_PASSWORD}" ]; then
  PANEL_PASSWORD="$(random_alnum 18)"
fi
if [ -z "${PANEL_ENTRANCE}" ]; then
  PANEL_ENTRANCE="$(random_alnum 10)"
fi
if [ -z "${VERSION}" ] && [ -f "${SCRIPT_DIR}/opt/openpanel/self/VERSION" ]; then
  VERSION="$(cat "${SCRIPT_DIR}/opt/openpanel/self/VERSION")"
fi
VERSION="${VERSION:-v2.0.0-open}"

install_basic_packages() {
  if [ "${SKIP_APT}" = "true" ]; then
    return
  fi
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates curl python3
  fi
}

stop_services() {
  systemctl stop 1panel-core.service 2>/dev/null || true
  systemctl stop 1panel-agent.service 2>/dev/null || true
}

reset_data_if_requested() {
  if [ "${RESET_DATA}" != "true" ]; then
    return
  fi
  local data_dir="${BASE_DIR%/}/1panel"
  if [ -e "${data_dir}" ]; then
    local backup="${data_dir}.backup.$(date +%Y%m%d%H%M%S)"
    mv "${data_dir}" "${backup}"
    echo "moved existing data to ${backup}"
  fi
}

install_files() {
  install -m 0755 "${SCRIPT_DIR}/usr/local/bin/1panel-core" /usr/local/bin/1panel-core
  install -m 0755 "${SCRIPT_DIR}/usr/local/bin/1panel-agent" /usr/local/bin/1panel-agent
  install -m 0644 "${SCRIPT_DIR}/etc/systemd/system/1panel-core.service" /etc/systemd/system/1panel-core.service
  install -m 0644 "${SCRIPT_DIR}/etc/systemd/system/1panel-agent.service" /etc/systemd/system/1panel-agent.service

  mkdir -p \
    "${BASE_DIR%/}/1panel/conf" \
    "${BASE_DIR%/}/1panel/db" \
    "${BASE_DIR%/}/1panel/log" \
    "${BASE_DIR%/}/1panel/geo" \
    /etc/1panel \
    /opt/openpanel/self

  chmod 0700 /etc/1panel
  if [ -d "${SCRIPT_DIR}/opt/openpanel/self" ]; then
    cp -a "${SCRIPT_DIR}/opt/openpanel/self/." /opt/openpanel/self/
  fi
}

write_app_config() {
  local app_yaml="${BASE_DIR%/}/1panel/conf/app.yaml"
  if [ "${PRESERVE_CONFIG}" = "true" ] && [ "${RESET_DATA}" != "true" ] && [ -s "${app_yaml}" ]; then
    echo "preserved existing app config: ${app_yaml}"
    return
  fi
  cat >"${app_yaml}" <<EOF_APP
base:
  install_dir: ${BASE_DIR}
  mode: dev
  is_demo: false
  is_offline: false
  is_fxplay: false
  is_enterprise: false
  edition: cn
  username: ${PANEL_USERNAME}
  password: ${PANEL_PASSWORD}
  language: ${LANGUAGE}
  version: ${VERSION}

conn:
  port: "${PANEL_PORT}"
  bindAddress: "0.0.0.0"
  ipv6: Disable
  ssl: Disable
  entrance: ${PANEL_ENTRANCE}

log:
  level: info
  time_zone: Asia/Shanghai
  log_name: 1Panel
  log_suffix: .log
  max_backup: 10
EOF_APP
  chmod 0600 "${app_yaml}"
}

write_ctl() {
  local ctl="/usr/local/bin/1pctl"
  cat >"${ctl}" <<EOF_CTL_HEAD
#!/usr/bin/env bash
BASE_DIR=${BASE_DIR}
ORIGINAL_PORT=${PANEL_PORT}
ORIGINAL_VERSION=${VERSION}
ORIGINAL_USERNAME=${PANEL_USERNAME}
ORIGINAL_PASSWORD=${PANEL_PASSWORD}
ORIGINAL_ENTRANCE=${PANEL_ENTRANCE}
LANGUAGE=${LANGUAGE}
PANEL_EDITION=cn
EOF_CTL_HEAD
  cat >>"${ctl}" <<'EOF_CTL_BODY'
set -Eeuo pipefail

service_cmd() {
  local action="$1"
  systemctl "${action}" 1panel-agent.service
  systemctl "${action}" 1panel-core.service
}

user_info() {
  local info="${BASE_DIR%/}/1panel/conf/install-info"
  if [ -f "${info}" ]; then
    cat "${info}"
    return
  fi
  echo "URL: http://<server-ip>:${ORIGINAL_PORT}/${ORIGINAL_ENTRANCE}"
  echo "Username: ${ORIGINAL_USERNAME}"
  echo "Password: ${ORIGINAL_PASSWORD}"
}

api_config() {
  local status="${1:-Enable}"
  local key="${2:-}"
  local whitelist="${3:-127.0.0.1}"
  local validity="${4:-0}"
  local db="${BASE_DIR%/}/1panel/db/core.db"
  python3 - "${db}" "${status}" "${key}" "${whitelist}" "${validity}" <<'PY'
import sqlite3
import sys
from datetime import datetime

db, status, key, whitelist, validity = sys.argv[1:6]
conn = sqlite3.connect(db)
now = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
settings = {
    "ApiInterfaceStatus": status,
    "ApiKey": key,
    "IpWhiteList": whitelist.replace(",", "\n"),
    "ApiKeyValidityTime": str(validity),
}
for k, v in settings.items():
    row = conn.execute("select id from settings where key = ?", (k,)).fetchone()
    if row:
        conn.execute("update settings set value = ?, updated_at = ? where key = ?", (v, now, k))
    else:
        conn.execute(
            "insert into settings (created_at, updated_at, key, value, about) values (?, ?, ?, ?, '')",
            (now, now, k, v),
        )
conn.commit()
conn.close()
PY
}

case "${1:-}" in
  start) service_cmd start ;;
  stop) service_cmd stop ;;
  restart) service_cmd restart ;;
  status) systemctl status 1panel-core.service 1panel-agent.service ;;
  logs) journalctl -u 1panel-core.service -u 1panel-agent.service -f ;;
  user-info) user_info ;;
  api-config) shift; api_config "$@" ;;
  *)
    echo "Usage: 1pctl {start|stop|restart|status|logs|user-info|api-config}" >&2
    exit 1
    ;;
esac
EOF_CTL_BODY
  chmod 0755 "${ctl}"
}

wait_for_core_db() {
  local db="${BASE_DIR%/}/1panel/db/core.db"
  for _ in $(seq 1 60); do
    if [ -s "${db}" ] && python3 - "${db}" <<'PY' >/dev/null 2>&1
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
row = conn.execute("select value from settings where key = 'ServerPort'").fetchone()
conn.close()
if row is None:
    raise SystemExit(1)
PY
    then
      return 0
    fi
    sleep 2
  done
  echo "core database did not become ready in time" >&2
  return 1
}

write_install_info() {
  local info="${BASE_DIR%/}/1panel/conf/install-info"
  {
    echo "Role: ${ROLE}"
    echo "URL: http://<server-ip>:${PANEL_PORT}/${PANEL_ENTRANCE}"
    echo "Username: ${PANEL_USERNAME}"
    echo "Password: ${PANEL_PASSWORD}"
    if [ -n "${API_KEY}" ]; then
      echo "API Key: ${API_KEY}"
      echo "API Whitelist:"
      normalize_list "${API_WHITELIST}" | sed 's/^/  /'
    fi
  } >"${info}"
  chmod 0600 "${info}"
}

enable_api_if_requested() {
  if [ -z "${API_KEY}" ]; then
    return
  fi
  wait_for_core_db
  systemctl stop 1panel-core.service
  /usr/local/bin/1pctl api-config Enable "${API_KEY}" "$(normalize_list "${API_WHITELIST}")" "${API_VALIDITY}"
  systemctl start 1panel-core.service
}

main() {
  install_basic_packages
  stop_services
  reset_data_if_requested
  install_files
  write_app_config
  write_ctl
  write_install_info

  systemctl daemon-reload
  systemctl enable --now 1panel-agent.service
  systemctl enable --now 1panel-core.service
  enable_api_if_requested

  echo "installed ${ROLE} node"
  /usr/local/bin/1pctl user-info
}

main "$@"
