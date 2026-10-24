#!/usr/bin/env bash
# The warehouse stack picks one of redshift-serverless and redshift-cluster by warehouse_mode and publishes the same
# SSM keys either way (design v7 section 7.3), so both modules must declare these outputs.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
other="${here}/../redshift-cluster"
required=(endpoint_address port database_name admin_secret_arn)

dirs=("$here")
# A repo that vendors only this module has no sibling to compare against.
if [ -d "$other" ]; then dirs+=("$other"); else echo "SKIP output parity: redshift-cluster is not in this repo"; fi

fail=0
for dir in "${dirs[@]}"; do
  for name in "${required[@]}"; do
    if ! grep -qE "^output[[:space:]]+\"${name}\"[[:space:]]*\\{" "${dir}/outputs.tf"; then
      echo "FAIL ${dir##*/modules/}/outputs.tf 缺少 output \"${name}\"（redshift-serverless 與 redshift-cluster 必須同名）" >&2
      fail=1
    fi
  done
done
[ "$fail" -eq 0 ] && echo "OK output parity: ${required[*]}"
exit "$fail"
