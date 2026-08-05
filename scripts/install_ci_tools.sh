#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# The path is resolved from this script at runtime.
# shellcheck disable=SC1091
source "$repo_root/versions.env"
tool_bin_dir=${TOOL_BIN_DIR:-$repo_root/.tools/bin}
tool_download_dir=$(mktemp -d)
install -d -m 0755 "$tool_bin_dir"

download() {
  local url=$1 destination=$2 checksum=$3
  curl --fail --silent --show-error --location "$url" -o "$destination"
  printf '%s  %s\n' "$checksum" "$destination" | sha256sum --check --status
}

download "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip" \
  "$tool_download_dir/tflint.zip" cca9d13e2e1d7a2c627af60ff899a3c9b74212899416aeb96ec764d2ef954537
unzip -q "$tool_download_dir/tflint.zip" -d "$tool_bin_dir"

download "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
  "$tool_download_dir/trivy.tar.gz" 2edd39da482bb4e9831962487b68f68e3928ec3137794757f54d00383d79547b
tar -xzf "$tool_download_dir/trivy.tar.gz" -C "$tool_bin_dir" trivy

download "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" \
  "$tool_download_dir/actionlint.tar.gz" 8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
tar -xzf "$tool_download_dir/actionlint.tar.gz" -C "$tool_bin_dir" actionlint

download "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
  "$tool_download_dir/gitleaks.tar.gz" 551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
tar -xzf "$tool_download_dir/gitleaks.tar.gz" -C "$tool_bin_dir" gitleaks

download "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" \
  "$tool_download_dir/shellcheck.tar.xz" 8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
tar -xJf "$tool_download_dir/shellcheck.tar.xz" -C "$tool_download_dir"
install -m 0755 "$tool_download_dir/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" "$tool_bin_dir/shellcheck"

if [[ -n ${GITHUB_PATH:-} ]]; then
  printf '%s\n' "$tool_bin_dir" >> "$GITHUB_PATH"
else
  printf 'Add %s to PATH\n' "$tool_bin_dir"
fi
