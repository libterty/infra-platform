#!/usr/bin/env bash
# Offline validation: fmt, static rules, init -backend=false, validate, test (mock), tflint. Never touches AWS.
# Usage: scripts/validate.sh [dir...]   Without arguments, scans modules and templates.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache_root="${repo_root}/.cache"
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-${cache_root}/plugins}"
mkdir -p "${TF_PLUGIN_CACHE_DIR}"
# Modules have no lock file; without this flag terraform skips the cache and re-downloads providers per directory.
# Template stacks are still checked against their lock file with -lockfile=readonly.
export TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true

# Step 0: second line of defense. A test missing mock_provider must fail, not pick up a local aws-vault session.
for v in $(env | sed -n 's/^\(AWS_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export AWS_CONFIG_FILE=/dev/null
export AWS_SHARED_CREDENTIALS_FILE=/dev/null
export AWS_EC2_METADATA_DISABLED=true

tf_stack_glob="templates/project-infra/infra/terraform"

# S8 allow-list, one entry per row of the table in docs/design/v1/design-docs.md section 5.3
# (native resources allowed in template stacks). Format: <stack>:<resource type>.
s8_allowed=(
  "foundation:aws_secretsmanager_secret"
)

command -v terraform >/dev/null || { echo "找不到 terraform" >&2; exit 1; }

# Print the path relative to repo_root; paths outside the repo are returned as is.
rel() {
  case "$1" in
    "${repo_root}"/*) printf '%s\n' "${1#"${repo_root}"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# Step 1: find directories. Never scan from the repo root: docs/slides/ has .tf files that exist locally but not in CI.
scan_roots=()
dirs=()
if [ "$#" -eq 0 ]; then
  for r in modules templates; do
    [ -d "${repo_root}/${r}" ] && scan_roots+=("${repo_root}/${r}")
  done
  for d in "${repo_root}"/modules/* "${repo_root}"/modules/*/examples/* "${repo_root}/${tf_stack_glob}"/*; do
    [ -d "$d" ] || continue
    ls "$d"/*.tf >/dev/null 2>&1 && dirs+=("$d")
  done
else
  for a in "$@"; do
    [ -d "$a" ] || { echo "不是目錄：$a" >&2; exit 1; }
    scan_roots+=("$(cd "$a" && pwd)")
  done
  for r in "${scan_roots[@]}"; do
    while IFS= read -r d; do dirs+=("$d"); done < <(
      find "$r" -name '*.tf' -not -path '*/.terraform*' -exec dirname {} \; | sort -u
    )
  done
fi

failed=()
fail_static=0

# Step 2: fmt. Does not abort, so the static rules still run and all problems are listed at once.
if [ "${#scan_roots[@]}" -gt 0 ]; then
  echo "== fmt"
  if ! terraform fmt -check -recursive "${scan_roots[@]}"; then
    echo "FAIL fmt：上面列出的檔案格式不符，執行 terraform fmt 修正" >&2
    fail_static=1
  fi
fi

# Step 3: static rules. Each prints "S<n> <relative path>[:line]: message". S5 always scans the whole template set.
echo "== 靜態規則"
files_tf=()
files_tftest=()
files_tfbackend=()
for r in ${scan_roots[@]+"${scan_roots[@]}"}; do
  while IFS= read -r f; do files_tf+=("$f"); done < <(find "$r" -name '*.tf' -not -path '*/.terraform*' | sort)
  while IFS= read -r f; do files_tftest+=("$f"); done < <(find "$r" -name '*.tftest.hcl' -not -path '*/.terraform*' | sort)
  while IFS= read -r f; do files_tfbackend+=("$f"); done < <(find "$r" -name '*.tfbackend' -not -path '*/.terraform*' | sort)
done

# Report non-comment lines matching an awk regex; any hit fails.
# $1=rule id, $2=message, $3=file, $4=regex, $5=optional regex of lines to ignore
scan_pattern() {
  local out
  out="$(awk -v pat="$4" -v ex="${5:-}" '/^[[:space:]]*(#|\/\/)/ { next } $0 ~ pat && (ex == "" || $0 !~ ex) { print FNR ": " $0 }' "$3")"
  if [ -n "$out" ]; then
    while IFS= read -r line; do echo "$1 $(rel "$3"):${line}  <- $2" >&2; done <<<"$out"
    fail_static=1
  fi
}

# S8: true when "<stack>:<type>" is in s8_allowed.
s8_is_allowed() {
  local entry
  for entry in "${s8_allowed[@]}"; do
    [ "$entry" = "$1:$2" ] && return 0
  done
  return 1
}

# S8: report every resource "aws_*" in a stack file that is not in s8_allowed. $1=file, $2=stack
scan_stack_resources() {
  local ln type
  while IFS=: read -r ln type; do
    [ -n "$type" ] || continue
    if ! s8_is_allowed "$2" "$type"; then
      echo "S8 $(rel "$1"):${ln}: stack ${2} 不得宣告 ${type}（不在 design §5.3 例外清單）" >&2
      fail_static=1
    fi
  done < <(awk '/^[[:space:]]*(#|\/\/)/ { next }
    match($0, /^[[:space:]]*resource[[:space:]]+"aws_[^"]*"/) {
      t = substr($0, RSTART, RLENGTH); sub(/^[^"]*"/, "", t); sub(/"$/, "", t); print FNR ":" t
    }' "$1")
}

# S1: every test file declares mock_provider "aws"
for f in ${files_tftest[@]+"${files_tftest[@]}"}; do
  if ! grep -Eq '^[[:space:]]*mock_provider[[:space:]]+"aws"' "$f"; then
    echo "S1 $(rel "$f"): 測試檔缺 mock_provider \"aws\"" >&2
    fail_static=1
  fi
done

for f in ${files_tf[@]+"${files_tf[@]}"}; do
  r="$(rel "$f")"
  # S2: aws_ssm_parameter resources only in modules/ssm-publish
  case "$r" in
    modules/ssm-publish/*) ;;
    *) scan_pattern S2 'aws_ssm_parameter 只能由 modules/ssm-publish 宣告' "$f" '^[[:space:]]*resource[[:space:]]+"aws_ssm_parameter"' ;;
  esac
  # S3: aws_ssm_parameter data sources only in modules/ssm-read, which must not read .value
  case "$r" in
    # each.value is a for_each iterator, not the parameter value.
    modules/ssm-read/*) scan_pattern S3 'modules/ssm-read 只能讀 insecure_value，不得出現 .value' "$f" '[.]value([^A-Za-z0-9_]|$)' '(^|[^A-Za-z0-9_])each[.]value([^A-Za-z0-9_]|$)' ;;
    *) scan_pattern S3 'data "aws_ssm_parameter" 只能出現在 modules/ssm-read' "$f" '^[[:space:]]*data[[:space:]]+"aws_ssm_parameter"' ;;
  esac
  case "$r" in
    modules/* | templates/*)
      # S4: IAM only in iam-role (all types) and iam-role-policy (aws_iam_role_policy only)
      case "$r" in
        modules/iam-role/*) ;;
        modules/iam-role-policy/*) scan_pattern S4 'modules/iam-role-policy 只允許 aws_iam_role_policy' "$f" '^[[:space:]]*resource[[:space:]]+"aws_iam_' '"aws_iam_role_policy"' ;;
        *) scan_pattern S4 'aws_iam_* 只能出現在 modules/iam-role 與 modules/iam-role-policy' "$f" '^[[:space:]]*resource[[:space:]]+"aws_iam_' ;;
      esac
      # S4: security groups and their rules only in security-group and vpc-interface-endpoints
      case "$r" in
        modules/security-group/* | modules/vpc-interface-endpoints/*) ;;
        *) scan_pattern S4 'aws_security_group* 與 aws_vpc_security_group_*_rule 只能出現在 modules/security-group 與 modules/vpc-interface-endpoints' "$f" '^[[:space:]]*resource[[:space:]]+"(aws_security_group|aws_vpc_security_group_(ingress|egress)_rule)' ;;
      esac
      # S4: the default security group is adopted only by the module that creates the VPC
      case "$r" in
        modules/vpc/*) ;;
        *) scan_pattern S4 'aws_default_security_group 只能出現在 modules/vpc' "$f" '^[[:space:]]*resource[[:space:]]+"aws_default_security_group"' ;;
      esac
      ;;
  esac
  case "$r" in
    modules/*)
      # S7: no random_password in modules
      scan_pattern S7 'modules 不得使用 random_password' "$f" 'random_password'
      ;;
  esac
  # S7: rds must not declare a password variable
  if [ "$r" = "modules/rds/variables.tf" ]; then
    scan_pattern S7 'rds 不得宣告含 password 的變數' "$f" '^[[:space:]]*variable[[:space:]]+"[^"]*[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][^"]*"'
  fi
  # S8: template stacks only declare the aws_* resources listed in s8_allowed
  case "$r" in
    "${tf_stack_glob}"/*)
      stack="${r#"${tf_stack_glob}"/}"
      scan_stack_resources "$f" "${stack%%/*}"
      ;;
  esac
done

# S5: common.tf must be identical across template stacks
first_common=""
first_hash=""
for f in "${repo_root}/${tf_stack_glob}"/*/common.tf; do
  [ -f "$f" ] || continue
  h="$(sha256 "$f")"
  if [ -z "$first_hash" ]; then
    first_common="$f"
    first_hash="$h"
  elif [ "$h" != "$first_hash" ]; then
    echo "S5 $(rel "$f"): common.tf 與 $(rel "$first_common") 不同" >&2
    fail_static=1
  fi
done

# S6: tfbackend key must be <project>-<env>/<stack>/terraform.tfstate; envs/examples/ must not have tfbackend
for f in ${files_tfbackend[@]+"${files_tfbackend[@]}"}; do
  r="$(rel "$f")"
  case "$r" in
    */envs/examples/*)
      echo "S6 ${r}: envs/examples/ 不得有 tfbackend" >&2
      fail_static=1
      continue
      ;;
  esac
  env_name="$(basename "$f" .tfbackend)"
  stack="$(basename "$(dirname "$(dirname "$f")")")"
  key="$(awk -F'=' '/^[[:space:]]*key[[:space:]]*=/ { v=$2; gsub(/[[:space:]"]/, "", v); print v; exit }' "$f")"
  if ! printf '%s\n' "$key" | grep -Eq "^[^/]+-${env_name}/${stack}/terraform\\.tfstate\$"; then
    echo "S6 ${r}: key=\"${key}\" 應為 <project>-${env_name}/${stack}/terraform.tfstate" >&2
    fail_static=1
  fi
done

if [ "$fail_static" -ne 0 ]; then
  echo "FAIL fmt 或靜態規則未過，不進入後面的驗證步驟" >&2
  exit 1
fi

if [ "${#dirs[@]}" -eq 0 ]; then
  echo "沒有找到要驗證的目錄"
  exit 0
fi

command -v tflint >/dev/null || { echo "找不到 tflint" >&2; exit 1; }

# Steps 4-7: init, validate, test, tflint for one directory.
validate_dir() {
  local dir="$1" r data_dir lock=()
  r="$(rel "$dir")"
  data_dir="${cache_root}/tf-data/$(printf '%s' "$r" | sed 's|^/||; s|/|__|g')"
  export TF_DATA_DIR="$data_dir"
  case "$r" in
    "${tf_stack_glob}"/*) lock=(-lockfile=readonly) ;;
  esac

  echo "== ${r}"
  terraform -chdir="$dir" init -backend=false -input=false ${lock[@]+"${lock[@]}"} || return 1
  terraform -chdir="$dir" validate || return 1

  if [ -d "$dir/tests" ]; then
    terraform -chdir="$dir" test || return 1
  fi

  # Step 6a: template stacks run tests against the tfvars files themselves.
  case "$r" in
    "${tf_stack_glob}"/*)
      local e x
      for e in dev prod; do
        if [ -f "$dir/envs/$e.tfvars" ] && [ -d "$dir/tests/tfvars" ]; then
          terraform -chdir="$dir" test -test-directory=tests/tfvars -var-file="envs/$e.tfvars" || return 1
        fi
      done
      for x in "$dir"/envs/examples/*.tfvars; do
        [ -f "$x" ] && [ -d "$dir/tests/examples" ] || continue
        terraform -chdir="$dir" test -test-directory=tests/examples -var-file="envs/examples/$(basename "$x")" || return 1
      done
      ;;
  esac

  tflint --chdir="$dir" --config="${repo_root}/.tflint.hcl" || return 1
}

for d in "${dirs[@]}"; do
  rc=0
  validate_dir "$d" || rc=1
  # Step 8: modules do not commit lock files; remove the one init created.
  case "$(rel "$d")" in
    modules/*) rm -f "$d/.terraform.lock.hcl" ;;
  esac
  if [ "$rc" -ne 0 ]; then
    failed+=("$(rel "$d")")
  fi
done

# Step 9: summary.
if [ "${#failed[@]}" -gt 0 ]; then
  echo "" >&2
  echo "FAIL 以下目錄未通過：" >&2
  printf '  %s\n' "${failed[@]}" >&2
  exit 1
fi
echo "OK：${#dirs[@]} 個目錄全部通過"
