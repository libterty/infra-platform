#!/usr/bin/env bash
# Static check of the warehouse_mode guard (design section 7.3). terraform test cannot see prevent_destroy: a plan run
# has no existing state, so nothing is ever replaced. This script reads HCL only; it is offline and needs no init.
# It fails when guard.tf loses `prevent_destroy = true` or `triggers_replace = var.warehouse_mode`, or when either
# Redshift module stops depending on the guard.
set -euo pipefail

stack="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
errors=0
fail() {
  echo "FAIL check-warehouse-guard: $*" >&2
  errors=$((errors + 1))
}

guard="${stack}/guard.tf"
[ -f "$guard" ] || { echo "FAIL check-warehouse-guard: guard.tf is missing" >&2; exit 1; }

# Ignore comments so a commented-out setting does not count.
code="$(sed -E 's/[[:space:]]*(#|\/\/).*$//' "$guard")"

grep -qE '^resource "terraform_data" "warehouse_mode_guard" \{' <<<"$code" ||
  fail 'guard.tf must declare resource "terraform_data" "warehouse_mode_guard"'
grep -qE '^[[:space:]]*triggers_replace[[:space:]]*=[[:space:]]*var\.warehouse_mode[[:space:]]*$' <<<"$code" ||
  fail 'guard.tf: triggers_replace must be exactly var.warehouse_mode'
grep -qE '^[[:space:]]*prevent_destroy[[:space:]]*=[[:space:]]*true[[:space:]]*$' <<<"$code" ||
  fail 'guard.tf: lifecycle must set prevent_destroy = true (a local unlock must never be committed, design K23)'
if grep -qE 'prevent_destroy[[:space:]]*=[[:space:]]*(false|[^t[:space:]])' <<<"$code"; then
  fail 'guard.tf: prevent_destroy must be the literal true'
fi

# Both Redshift module blocks must list the guard in depends_on.
for m in serverless provisioned; do
  block="$(awk -v m="$m" '
    $0 ~ "^module \"" m "\" \\{" { on = 1 }
    on { print }
    on && /^}/ { exit }
  ' "${stack}"/*.tf | sed -E 's/[[:space:]]*(#|\/\/).*$//')"
  [ -n "$block" ] || { fail "module \"${m}\" is missing"; continue; }
  grep -qE '^[[:space:]]*depends_on[[:space:]]*=[[:space:]]*\[terraform_data\.warehouse_mode_guard\][[:space:]]*$' <<<"$block" ||
    fail "module \"${m}\" must have depends_on = [terraform_data.warehouse_mode_guard]"
done

if [ "$errors" -gt 0 ]; then
  exit 1
fi
echo "OK check-warehouse-guard: prevent_destroy = true, triggers_replace = var.warehouse_mode, both modules depend on the guard"
