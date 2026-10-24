#!/usr/bin/env bash
# read_master_secret = false exists only so terraform test can skip the ephemeral read offline. A tfvars file that
# sets it would deploy search-config without the master credentials, so no tfvars may set it at all.
set -euo pipefail

stack="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if grep -rnE '^[[:space:]]*read_master_secret[[:space:]]*=' "$stack"/envs --include='*.tfvars'; then
  echo "FAIL check-read-master-secret: tfvars must not set read_master_secret (it is for offline tests only)" >&2
  exit 1
fi
echo "OK check-read-master-secret: no tfvars sets read_master_secret"
