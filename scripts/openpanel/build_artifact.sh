#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GOOS="${GOOS:-linux}"
GOARCH="${GOARCH:-amd64}"
VERSION="${VERSION:-v2.0.0-open.$(date +%Y%m%d%H%M%S)}"
VERSION="${VERSION#openpanel-}"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build/openpanel}"
DIST_DIR="${BUILD_DIR}/dist"
ARTIFACT="${BUILD_DIR}/openpanel-${VERSION}-${GOOS}-${GOARCH}.tar.gz"
PACKAGE_NAME="openpanel-${VERSION}-${GOOS}-${GOARCH}"
PACKAGE_DIR="${DIST_DIR}/${PACKAGE_NAME}"
INSTALLER_DIR="${SCRIPT_DIR}/installer"
GEOIP_URL="${OPENPANEL_GEOIP_URL:-https://resource.fit2cloud.com/1panel/package/v2/geo/GeoIP.mmdb}"
GEOIP_FILE="${BUILD_DIR}/GeoIP.mmdb"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

download_file() {
  local url="$1"
  local output="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 2 -o "${output}" "${url}"
    return
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -O "${output}" "${url}"
    return
  fi
  echo "missing required command: curl or wget" >&2
  exit 1
}

ensure_installer_inputs() {
  local required=(
    "${INSTALLER_DIR}/install.sh"
    "${INSTALLER_DIR}/1pctl"
    "${INSTALLER_DIR}/initscript/1panel-core.service"
    "${INSTALLER_DIR}/initscript/1panel-agent.service"
    "${INSTALLER_DIR}/lang/en.sh"
    "${INSTALLER_DIR}/lang/zh.sh"
  )

  for file in "${required[@]}"; do
    if [ ! -f "${file}" ]; then
      echo "missing installer input: ${file}" >&2
      exit 1
    fi
  done
}

ensure_geoip() {
  if [ -s "${GEOIP_FILE}" ]; then
    return
  fi
  mkdir -p "$(dirname "${GEOIP_FILE}")"
  download_file "${GEOIP_URL}" "${GEOIP_FILE}"
}

ensure_embed_inputs() {
  local web_dir="${ROOT_DIR}/core/cmd/server/web"
  mkdir -p "${web_dir}/assets" "${web_dir}/static"
  if [ ! -e "${web_dir}/assets/.keep" ] && ! find "${web_dir}/assets" -mindepth 1 -print -quit | grep -q .; then
    : >"${web_dir}/assets/.keep"
  fi
  if [ ! -e "${web_dir}/static/.keep" ] && ! find "${web_dir}/static" -mindepth 1 -print -quit | grep -q .; then
    : >"${web_dir}/static/.keep"
  fi
  if [ ! -f "${web_dir}/index.html" ]; then
    printf '<!doctype html><html><head><meta charset="utf-8"><title>OpenPanel</title></head><body></body></html>\n' >"${web_dir}/index.html"
  fi
  if [ ! -f "${web_dir}/favicon.png" ]; then
    cp "${ROOT_DIR}/core/cmd/server/app/logo.png" "${web_dir}/favicon.png"
  fi
}

build_frontend() {
  local web_go_tmp
  web_go_tmp="$(mktemp)"
  cp "${ROOT_DIR}/core/cmd/server/web/web.go" "${web_go_tmp}"

  (
    cd "${ROOT_DIR}/frontend"
    if [ -f package-lock.json ]; then
      npm ci
    else
      npm install
    fi
    npm run build:pro
  )

  if [ ! -f "${ROOT_DIR}/core/cmd/server/web/web.go" ]; then
    cp "${web_go_tmp}" "${ROOT_DIR}/core/cmd/server/web/web.go"
  fi
  rm -f "${web_go_tmp}"
  ensure_embed_inputs
}

build_binary() {
  local module_dir="$1"
  local output="$2"
  (
    cd "${ROOT_DIR}/${module_dir}"
    CGO_ENABLED=0 GOOS="${GOOS}" GOARCH="${GOARCH}" \
      go build -trimpath -ldflags '-s -w' -o "${output}" ./cmd/server
  )
}

package_artifact() {
  rm -rf "${DIST_DIR}"
  mkdir -p \
    "${PACKAGE_DIR}/initscript" \
    "${PACKAGE_DIR}/lang" \
    "${PACKAGE_DIR}/usr/local/bin" \
    "${PACKAGE_DIR}/etc/systemd/system" \
    "${PACKAGE_DIR}/opt/openpanel/self"

  install -m 0755 "${BUILD_DIR}/1panel-core" "${PACKAGE_DIR}/1panel-core"
  install -m 0755 "${BUILD_DIR}/1panel-agent" "${PACKAGE_DIR}/1panel-agent"
  install -m 0755 "${INSTALLER_DIR}/install.sh" "${PACKAGE_DIR}/install.sh"
  install -m 0755 "${INSTALLER_DIR}/1pctl" "${PACKAGE_DIR}/1pctl"
  install -m 0644 "${INSTALLER_DIR}/LICENSE" "${PACKAGE_DIR}/LICENSE.installer"
  install -m 0644 "${INSTALLER_DIR}/initscript/1panel-core.service" "${PACKAGE_DIR}/1panel-core.service"
  install -m 0644 "${INSTALLER_DIR}/initscript/1panel-agent.service" "${PACKAGE_DIR}/1panel-agent.service"
  cp -a "${INSTALLER_DIR}/initscript/." "${PACKAGE_DIR}/initscript/"
  cp -a "${INSTALLER_DIR}/lang/." "${PACKAGE_DIR}/lang/"
  install -m 0644 "${GEOIP_FILE}" "${PACKAGE_DIR}/GeoIP.mmdb"

  install -m 0755 "${SCRIPT_DIR}/install_node.sh" "${PACKAGE_DIR}/install_node.sh"
  install -m 0755 "${BUILD_DIR}/1panel-core" "${PACKAGE_DIR}/usr/local/bin/1panel-core"
  install -m 0755 "${BUILD_DIR}/1panel-agent" "${PACKAGE_DIR}/usr/local/bin/1panel-agent"
  install -m 0644 "${INSTALLER_DIR}/initscript/1panel-core.service" "${PACKAGE_DIR}/etc/systemd/system/1panel-core.service"
  install -m 0644 "${INSTALLER_DIR}/initscript/1panel-agent.service" "${PACKAGE_DIR}/etc/systemd/system/1panel-agent.service"

  cat >"${PACKAGE_DIR}/opt/openpanel/self/VERSION" <<EOF_VERSION
${VERSION}
EOF_VERSION

  cat >"${PACKAGE_DIR}/opt/openpanel/self/MANIFEST" <<EOF_MANIFEST
name=openpanel-self
version=${VERSION}
goos=${GOOS}
goarch=${GOARCH}
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
source=${ROOT_DIR}
EOF_MANIFEST

  mkdir -p "${BUILD_DIR}"
  tar -C "${DIST_DIR}" -czf "${ARTIFACT}" "${PACKAGE_NAME}"
  printf '%s\n' "${ARTIFACT}"
}

main() {
  require_cmd go
  require_cmd npm
  require_cmd tar
  require_cmd find

  mkdir -p "${BUILD_DIR}"
  ensure_installer_inputs
  ensure_geoip
  ensure_embed_inputs
  build_frontend
  build_binary core "${BUILD_DIR}/1panel-core"
  build_binary agent "${BUILD_DIR}/1panel-agent"
  package_artifact
}

main "$@"
