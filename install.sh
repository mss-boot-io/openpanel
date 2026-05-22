#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${OPENPANEL_REPO:-mss-boot-io/openpanel}"
RELEASE="${OPENPANEL_RELEASE:-latest}"
ARTIFACT_URL="${OPENPANEL_ARTIFACT_URL:-}"
ROLE="master"
BASE_DIR=""
PANEL_PORT=""
PANEL_USERNAME=""
PANEL_PASSWORD=""
PANEL_ENTRANCE=""
LANGUAGE=""
API_KEY=""
API_WHITELIST=""
API_VALIDITY=""
RESET_DATA="false"
SKIP_APT="false"
PRESERVE_CONFIG="auto"
BACKUP_MODE="core"
WORK_DIR="/tmp/openpanel-install"

usage() {
  cat <<'EOF_USAGE'
OpenPanel one-click installer

Usage:
  bash install.sh [options]

Fresh install example:
  bash install.sh --role master --port 9999 --entrance openpanel

Upgrade an existing 1Panel/OpenPanel install in place:
  bash install.sh --role master --api-key YOUR_API_KEY

Options:
  --repo OWNER/REPO          GitHub repository. Default: mss-boot-io/openpanel.
  --release TAG|latest      Release tag or latest. Default: latest.
  --artifact-url URL        Direct artifact URL. Overrides --repo/--release.
  --role master|worker      Node role label. Default: master.
  --base-dir DIR            Existing install base dir. Auto-detected when omitted.
  --port PORT               Initial/fresh panel port.
  --username USER           Initial/fresh panel username.
  --password VALUE          Initial/fresh panel password.
  --entrance PATH           Initial/fresh security entrance.
  --language zh|en          Initial/fresh language.
  --api-key VALUE           Enable public API with this key.
  --api-whitelist VALUE     Comma/newline separated API whitelist.
  --api-validity MINUTES    API timestamp validity. 0 disables expiry.
  --preserve-config         Keep existing app.yaml. Default for existing installs.
  --no-preserve-config      Rewrite app.yaml from installer arguments.
  --backup-mode core|full|none
                           Existing install backup mode. Default: core.
                           core backs up conf/ and db/ only.
  --reset-data              Move existing <base-dir>/1panel aside first.
  --skip-apt                Do not install basic OS packages.
  -h, --help                Show this help.
EOF_USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_root() {
  [ "$(id -u)" = "0" ] || die "install.sh must run as root"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

download() {
  local url="$1"
  local output="$2"
  if has_cmd curl; then
    curl -fL --connect-timeout 20 --retry 3 --retry-delay 2 -o "${output}" "${url}"
    return
  fi
  if has_cmd wget; then
    wget -O "${output}" "${url}"
    return
  fi
  die "missing curl or wget"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'amd64' ;;
    aarch64|arm64) printf 'arm64' ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}

ctl_value() {
  local key="$1"
  local file="${2:-/usr/local/bin/1pctl}"
  [ -r "${file}" ] || return 0
  sed -n -E "s/^${key}=(.*)$/\1/p" "${file}" | head -n 1 | sed -E "s/^['\"]//; s/['\"]$//"
}

detect_base_dir() {
  local value candidate
  if [ -n "${BASE_DIR}" ]; then
    BASE_DIR="${BASE_DIR%/}"
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
  BASE_DIR="/opt"
}

existing_install() {
  [ -d "${BASE_DIR%/}/1panel" ]
}

backup_existing_install() {
  local data_dir="${BASE_DIR%/}/1panel"
  local backup_dir backup_file ts

  if [ "${RESET_DATA}" = "true" ] || [ "${BACKUP_MODE}" = "none" ] || ! existing_install; then
    return
  fi

  ts="$(date +%Y%m%d%H%M%S)"
  backup_dir="/root/openpanel-upgrade-backups"
  mkdir -p "${backup_dir}"
  backup_file="${backup_dir}/$(hostname)-${ts}-${BACKUP_MODE}.tar.gz"

  case "${BACKUP_MODE}" in
    core)
      local items=()
      [ -e "${data_dir}/conf" ] && items+=(conf)
      [ -e "${data_dir}/db" ] && items+=(db)
      [ "${#items[@]}" -gt 0 ] || return
      tar -C "${data_dir}" -czf "${backup_file}" "${items[@]}" || \
        die "failed to create core backup at ${backup_file}"
      ;;
    full)
      tar -C "${BASE_DIR%/}" -czf "${backup_file}" 1panel || \
        die "failed to create full backup at ${backup_file}"
      ;;
    *)
      die "--backup-mode must be core, full, or none"
      ;;
  esac

  chmod 0600 "${backup_file}"
  echo "backup: ${backup_file}"
}

artifact_download_url() {
  local arch="$1"
  if [ -n "${ARTIFACT_URL}" ]; then
    printf '%s\n' "${ARTIFACT_URL}"
    return
  fi
  if [ "${RELEASE}" = "latest" ]; then
    printf 'https://github.com/%s/releases/latest/download/openpanel-linux-%s.tar.gz\n' "${REPO}" "${arch}"
  else
    printf 'https://github.com/%s/releases/download/%s/openpanel-linux-%s.tar.gz\n' "${REPO}" "${RELEASE}" "${arch}"
  fi
}

checksum_download_url() {
  if [ "${RELEASE}" = "latest" ]; then
    printf 'https://github.com/%s/releases/latest/download/checksums.txt\n' "${REPO}"
  else
    printf 'https://github.com/%s/releases/download/%s/checksums.txt\n' "${REPO}" "${RELEASE}"
  fi
}

verify_checksum_if_available() {
  local checksum_url="$1"
  local artifact_name="$2"
  local checksum_file="${WORK_DIR}/checksums.txt"

  if ! has_cmd sha256sum; then
    return
  fi
  if ! download "${checksum_url}" "${checksum_file}" >/dev/null 2>&1; then
    echo "warning: checksums.txt is not available; skipped checksum verification" >&2
    return
  fi
  if ! grep -F "  ${artifact_name}" "${checksum_file}" >"${WORK_DIR}/checksum.current"; then
    echo "warning: checksum for ${artifact_name} not found; skipped checksum verification" >&2
    return
  fi
  (cd "${WORK_DIR}" && sha256sum -c checksum.current)
}

run_install_node() {
  local args=(
    bash "${WORK_DIR}/artifact/install_node.sh"
    --role "${ROLE}"
    --base-dir "${BASE_DIR}"
  )

  [ -n "${PANEL_PORT}" ] && args+=(--port "${PANEL_PORT}")
  [ -n "${PANEL_USERNAME}" ] && args+=(--username "${PANEL_USERNAME}")
  [ -n "${PANEL_PASSWORD}" ] && args+=(--password "${PANEL_PASSWORD}")
  [ -n "${PANEL_ENTRANCE}" ] && args+=(--entrance "${PANEL_ENTRANCE}")
  [ -n "${LANGUAGE}" ] && args+=(--language "${LANGUAGE}")
  [ -n "${API_KEY}" ] && args+=(--api-key "${API_KEY}")
  [ -n "${API_WHITELIST}" ] && args+=(--api-whitelist "${API_WHITELIST}")
  [ -n "${API_VALIDITY}" ] && args+=(--api-validity "${API_VALIDITY}")
  [ "${RESET_DATA}" = "true" ] && args+=(--reset-data)
  [ "${SKIP_APT}" = "true" ] && args+=(--skip-apt)
  if [ "${PRESERVE_CONFIG}" = "true" ] || { [ "${PRESERVE_CONFIG}" = "auto" ] && existing_install && [ "${RESET_DATA}" != "true" ]; }; then
    args+=(--preserve-config)
  fi

  "${args[@]}"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --release) RELEASE="$2"; shift 2 ;;
    --artifact-url) ARTIFACT_URL="$2"; shift 2 ;;
    --role) ROLE="$2"; shift 2 ;;
    --base-dir) BASE_DIR="$2"; shift 2 ;;
    --port) PANEL_PORT="$2"; shift 2 ;;
    --username) PANEL_USERNAME="$2"; shift 2 ;;
    --password) PANEL_PASSWORD="$2"; shift 2 ;;
    --entrance) PANEL_ENTRANCE="$2"; shift 2 ;;
    --language) LANGUAGE="$2"; shift 2 ;;
    --api-key) API_KEY="$2"; shift 2 ;;
    --api-whitelist) API_WHITELIST="$2"; shift 2 ;;
    --api-validity) API_VALIDITY="$2"; shift 2 ;;
    --preserve-config) PRESERVE_CONFIG="true"; shift ;;
    --no-preserve-config) PRESERVE_CONFIG="false"; shift ;;
    --backup-mode) BACKUP_MODE="$2"; shift 2 ;;
    --reset-data) RESET_DATA="true"; shift ;;
    --skip-apt) SKIP_APT="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

if [ "${ROLE}" != "master" ] && [ "${ROLE}" != "worker" ]; then
  die "--role must be master or worker"
fi

need_root
detect_base_dir
backup_existing_install

ARCH="$(detect_arch)"
ARTIFACT_NAME="openpanel-linux-${ARCH}.tar.gz"
ARTIFACT_PATH="${WORK_DIR}/${ARTIFACT_NAME}"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}/artifact"

URL="$(artifact_download_url "${ARCH}")"
echo "download: ${URL}"
download "${URL}" "${ARTIFACT_PATH}"
if [ -z "${ARTIFACT_URL}" ]; then
  verify_checksum_if_available "$(checksum_download_url)" "${ARTIFACT_NAME}"
fi
tar -xzf "${ARTIFACT_PATH}" -C "${WORK_DIR}/artifact"

echo "base dir: ${BASE_DIR}"
run_install_node
