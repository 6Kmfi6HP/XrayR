#!/usr/bin/env bash
set -euo pipefail

REPO="${XRAYR_REPO:-6Kmfi6HP/XrayR}"
API_BASE="${GITHUB_API_URL:-https://api.github.com}"
GITHUB_BASE="${GITHUB_SERVER_URL:-https://github.com}"
INSTALL_DIR="${XRAYR_INSTALL_DIR:-/usr/local/XrayR}"
CONFIG_DIR="${XRAYR_CONFIG_DIR:-/etc/XrayR}"
BIN_PATH="${XRAYR_BIN_PATH:-/usr/local/bin/XrayR}"
SERVICE_NAME="${XRAYR_SERVICE_NAME:-XrayR}"

usage() {
  cat <<USAGE
Usage: sudo bash install.sh [version]

Installs XrayR from ${GITHUB_BASE}/${REPO} releases.

Environment overrides:
  XRAYR_REPO=owner/repo
  XRAYR_INSTALL_DIR=/usr/local/XrayR
  XRAYR_CONFIG_DIR=/etc/XrayR
  XRAYR_BIN_PATH=/usr/local/bin/XrayR
USAGE
}

fail() {
  echo "error: $*" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required"
}

download_to_file() {
  local url="$1"
  local output="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 3 "$url" -o "$output"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$output" "$url"
  else
    fail "curl or wget is required"
  fi
}

download_stdout() {
  local url="$1"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --retry-delay 3 "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$url"
  else
    fail "curl or wget is required"
  fi
}

latest_version() {
  local payload
  local tag

  payload="$(download_stdout "${API_BASE}/repos/${REPO}/releases/latest")"
  tag="$(printf '%s' "$payload" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  [[ -n "$tag" ]] || fail "could not determine latest release tag"
  printf '%s\n' "$tag"
}

detect_asset_name() {
  local arch
  arch="$(uname -m)"

  case "$arch" in
    x86_64 | amd64)
      printf 'linux-64\n'
      ;;
    i386 | i686)
      printf 'linux-32\n'
      ;;
    aarch64 | arm64)
      printf 'linux-arm64-v8a\n'
      ;;
    armv7l | armv7*)
      printf 'linux-arm32-v7a\n'
      ;;
    armv6l | armv6*)
      printf 'linux-arm32-v6\n'
      ;;
    armv5tel | armv5*)
      printf 'linux-arm32-v5\n'
      ;;
    riscv64)
      printf 'linux-riscv64\n'
      ;;
    ppc64le)
      printf 'linux-ppc64le\n'
      ;;
    s390x)
      printf 'linux-s390x\n'
      ;;
    mips64le)
      printf 'linux-mips64le\n'
      ;;
    mips64)
      printf 'linux-mips64\n'
      ;;
    mipsle)
      printf 'linux-mips32le\n'
      ;;
    mips)
      printf 'linux-mips32\n'
      ;;
    *)
      fail "unsupported architecture: $arch"
      ;;
  esac
}

write_service() {
  local service_file="/etc/systemd/system/${SERVICE_NAME}.service"

  install -d -m 0755 /etc/systemd/system
  install -m 0644 /dev/stdin "$service_file" <<SERVICE
[Unit]
Description=XrayR Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${BIN_PATH} --config ${CONFIG_DIR}/config.yml
Restart=on-failure
RestartSec=10
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SERVICE
}

install_release() {
  local version="$1"
  local asset_name="$2"
  local tmp_dir
  local archive
  local asset_url

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  archive="${tmp_dir}/XrayR-${asset_name}.zip"
  asset_url="${GITHUB_BASE}/${REPO}/releases/download/${version}/XrayR-${asset_name}.zip"

  echo "Downloading ${asset_url}"
  download_to_file "$asset_url" "$archive"

  unzip -q "$archive" -d "${tmp_dir}/archive"
  [[ -f "${tmp_dir}/archive/XrayR" ]] || fail "release archive does not contain XrayR"

  install -d -m 0755 "$INSTALL_DIR" "$CONFIG_DIR" "$(dirname "$BIN_PATH")"
  install -m 0755 "${tmp_dir}/archive/XrayR" "$BIN_PATH"

  find "${tmp_dir}/archive" -maxdepth 1 -type f ! -name XrayR ! -name README.md ! -name LICENSE -print0 |
    while IFS= read -r -d '' file; do
      base_name="$(basename "$file")"
      if [[ "$base_name" == "config.yml" && -f "${CONFIG_DIR}/config.yml" ]]; then
        echo "Keeping existing ${CONFIG_DIR}/config.yml"
        continue
      fi
      install -m 0644 "$file" "${CONFIG_DIR}/${base_name}"
    done

  for file_name in README.md LICENSE; do
    if [[ -f "${tmp_dir}/archive/${file_name}" ]]; then
      install -m 0644 "${tmp_dir}/archive/${file_name}" "${INSTALL_DIR}/${file_name}"
    fi
  done

  write_service
}

main() {
  local version="${1:-${XRAYR_VERSION:-}}"
  local asset_name

  case "${version}" in
    -h | --help)
      usage
      exit 0
      ;;
  esac

  [[ "$(uname -s)" == "Linux" ]] || fail "this installer supports Linux only"
  [[ "${EUID}" -eq 0 ]] || fail "please run as root, for example: sudo bash install.sh"
  need_command unzip
  need_command install

  if [[ -z "$version" ]]; then
    version="$(latest_version)"
  fi
  asset_name="$(detect_asset_name)"

  install_release "$version" "$asset_name"

  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl restart "$SERVICE_NAME"
    echo "XrayR ${version} installed and ${SERVICE_NAME}.service restarted."
  else
    echo "XrayR ${version} installed. systemctl was not found, start it manually:"
    echo "  ${BIN_PATH} --config ${CONFIG_DIR}/config.yml"
  fi
}

main "$@"
