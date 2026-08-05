#!/usr/bin/env bash
set -euo pipefail

secret_dir=${RUNNER_TEMP:?RUNNER_TEMP is required}/aws-pam-secrets
if [[ -d $secret_dir ]]; then
  find "$secret_dir" -type f -exec shred -u -- {} + 2>/dev/null || true
  rmdir "$secret_dir" 2>/dev/null || true
fi

