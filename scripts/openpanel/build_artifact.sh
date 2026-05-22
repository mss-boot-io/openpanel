#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GOOS="${GOOS:-linux}"
GOARCH="${GOARCH:-amd64}"
VERSION="${VERSION:-v2.0.0-open.$(date +%Y%m%d%H%M%S)}"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build/openpanel}"
DIST_DIR="${BUILD_DIR}/dist"
ARTIFACT="${BUILD_DIR}/openpanel-${VERSION}-${GOOS}-${GOARCH}.tar.gz"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
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
    "${DIST_DIR}/usr/local/bin" \
    "${DIST_DIR}/etc/systemd/system" \
    "${DIST_DIR}/opt/openpanel/self"

  install -m 0755 "${BUILD_DIR}/1panel-core" "${DIST_DIR}/usr/local/bin/1panel-core"
  install -m 0755 "${BUILD_DIR}/1panel-agent" "${DIST_DIR}/usr/local/bin/1panel-agent"
  install -m 0755 "${SCRIPT_DIR}/install_node.sh" "${DIST_DIR}/install_node.sh"
  install -m 0644 "${SCRIPT_DIR}/templates/1panel-core.service" "${DIST_DIR}/etc/systemd/system/1panel-core.service"
  install -m 0644 "${SCRIPT_DIR}/templates/1panel-agent.service" "${DIST_DIR}/etc/systemd/system/1panel-agent.service"

  cat >"${DIST_DIR}/opt/openpanel/self/VERSION" <<EOF_VERSION
${VERSION}
EOF_VERSION

  cat >"${DIST_DIR}/opt/openpanel/self/MANIFEST" <<EOF_MANIFEST
name=openpanel-self
version=${VERSION}
goos=${GOOS}
goarch=${GOARCH}
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
source=${ROOT_DIR}
EOF_MANIFEST

  mkdir -p "${BUILD_DIR}"
  tar -C "${DIST_DIR}" -czf "${ARTIFACT}" .
  printf '%s\n' "${ARTIFACT}"
}

main() {
  require_cmd go
  require_cmd npm
  require_cmd tar
  require_cmd find

  mkdir -p "${BUILD_DIR}"
  ensure_embed_inputs
  build_frontend
  build_binary core "${BUILD_DIR}/1panel-core"
  build_binary agent "${BUILD_DIR}/1panel-agent"
  package_artifact
}

main "$@"
