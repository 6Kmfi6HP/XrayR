#!/usr/bin/env bash
set -euo pipefail

: "${GOOS:?GOOS is required}"
: "${GOARCH:?GOARCH is required}"
: "${ASSET_NAME:?ASSET_NAME is required}"

PROJECT_NAME="${PROJECT_NAME:-XrayR}"
VERSION="${VERSION:-dev}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
WORK_DIR="${WORK_DIR:-build_assets}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_PATH="github.com/6Kmfi6HP/XrayR"
PACKAGE_DIR="${PACKAGE_DIR:-${PROJECT_NAME}-${ASSET_NAME}}"

resolve_path() {
  case "$1" in
    /*)
      printf '%s\n' "$1"
      ;;
    *)
      printf '%s/%s\n' "$ROOT_DIR" "$1"
      ;;
  esac
}

archive_name="${PROJECT_NAME}-${ASSET_NAME}.zip"
work_path="$(resolve_path "$WORK_DIR")"
output_path="$(resolve_path "$OUTPUT_DIR")"
package_path="$(resolve_path "$PACKAGE_DIR")"

rm -rf "${work_path}" "${package_path}"
rm -f "${output_path}/${archive_name}" "${output_path}/${archive_name}.dgst"
mkdir -p "${work_path}" "${output_path}"

ldflags="-s -w -buildid= -X ${MODULE_PATH}/cmd.version=${VERSION#v}"
binary_path="${work_path}/${PROJECT_NAME}"
if [[ "${GOOS}" == "windows" ]]; then
  binary_path="${work_path}/${PROJECT_NAME}.exe"
fi

echo "Building ${PROJECT_NAME} ${VERSION} for ${GOOS}/${GOARCH}${GOARM:-}${GOMIPS:-}"
go build -v -o "${binary_path}" -trimpath -ldflags "${ldflags}"

if [[ "${GOARCH}" == "mips" || "${GOARCH}" == "mipsle" ]]; then
  echo "Building ${PROJECT_NAME}_softfloat for ${GOOS}/${GOARCH}"
  GOMIPS=softfloat go build -v -o "${work_path}/${PROJECT_NAME}_softfloat" -trimpath -ldflags "${ldflags}"
fi

cp "${ROOT_DIR}/README.md" "${work_path}/README.md"
cp "${ROOT_DIR}/LICENSE" "${work_path}/LICENSE"
cp "${ROOT_DIR}/release/config/dns.json" "${work_path}/dns.json"
cp "${ROOT_DIR}/release/config/route.json" "${work_path}/route.json"
cp "${ROOT_DIR}/release/config/custom_outbound.json" "${work_path}/custom_outbound.json"
cp "${ROOT_DIR}/release/config/custom_inbound.json" "${work_path}/custom_inbound.json"
cp "${ROOT_DIR}/release/config/rulelist" "${work_path}/rulelist"
cp "${ROOT_DIR}/release/config/config.yml.example" "${work_path}/config.yml"

while read -r repo asset file_name; do
  download_url="https://raw.githubusercontent.com/v2fly/${repo}/release/${asset}.dat"
  echo "Downloading ${download_url}"
  curl -fsSL --retry 5 --retry-delay 5 "${download_url}" -o "${work_path}/${file_name}.dat"
  expected_hash="$(curl -fsSL --retry 5 --retry-delay 5 "${download_url}.sha256sum" | awk '{print $1}')"
  actual_hash="$(sha256sum "${work_path}/${file_name}.dat" | awk '{print $1}')"
  if [[ "${actual_hash}" != "${expected_hash}" ]]; then
    echo "Hash mismatch for ${file_name}.dat" >&2
    echo "expected: ${expected_hash}" >&2
    echo "actual:   ${actual_hash}" >&2
    exit 1
  fi
done <<'GEODATA'
geoip geoip geoip
domain-list-community dlc geosite
GEODATA

pushd "${work_path}" >/dev/null
find . -exec touch -mt "$(date +%Y01010000)" {} +
zip -9qr "${output_path}/${archive_name}" .
popd >/dev/null

digest_file="${output_path}/${archive_name}.dgst"
for method in md5 sha1 sha256 sha512; do
  openssl dgst "-${method}" "${output_path}/${archive_name}" | sed 's/([^)]*)//g' >> "${digest_file}"
done

mv "${work_path}" "${package_path}"
echo "Wrote ${output_path}/${archive_name}"
echo "Wrote ${digest_file}"
