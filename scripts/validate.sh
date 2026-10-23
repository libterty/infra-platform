#!/usr/bin/env bash
# Validation: fmt, static rules, init -backend=false, validate, test (mock), tflint. Never touches AWS.
# Template stacks take their modules from the HCP private registry (ADR-0004), so they need a registry token
# (terraform login, or TF_TOKEN_app_terraform_io); modules and customer repos stay offline once the tflint plugins
# are in .cache/tflint-plugins (the first tflint --init downloads them from GitHub).
# Usage: scripts/validate.sh [dir...]   Without arguments, scans modules and templates.
#        scripts/validate.sh --changed-since <rev>   fmt and static rules scan everything; init/validate/test/tflint
#        only run in the directories a change since <rev> can affect (all of them when a shared file changed).
set -euo pipefail

changed_since=""
if [ "${1:-}" = "--changed-since" ]; then
  [ -n "${2:-}" ] || { echo "--changed-since 需要一個 git revision" >&2; exit 1; }
  changed_since="$2"
  shift 2
  [ "$#" -eq 0 ] || { echo "--changed-since 不能跟目錄一起用" >&2; exit 1; }
fi

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
# Same for Kubernetes and Helm: a test missing mock_provider "helm" must not reach a local cluster.
for v in $(env | sed -nE 's/^((KUBE|HELM)[A-Za-z0-9_]*)=.*/\1/p'); do unset "$v"; done
export KUBECONFIG=/dev/null

# Stack roots of every template (repo-relative), one per templates/<name>/infra/terraform.
tf_stack_roots=()
for d in "${repo_root}"/templates/*/infra/terraform; do
  [ -d "$d" ] && tf_stack_roots+=("${d#"${repo_root}"/}")
done
# A stack of a customer repo is judged by the rules of this template (S8 matches on the stack name only).
customer_stack_root="templates/project-infra/infra/terraform"

# S8 allow-list, one entry per row of the table in docs/design/v1/design-docs.md section 5.3
# (native resources allowed in template stacks, for every template). Format: <stack>:<resource type>.
s8_allowed=(
  "foundation:aws_secretsmanager_secret"
  "agent:aws_secretsmanager_secret"
)

command -v terraform >/dev/null || { echo "找不到 terraform" >&2; exit 1; }

# Print the path relative to repo_root; paths outside the repo are returned as is.
rel() {
  case "$1" in
    "${repo_root}"/*) printf '%s\n' "${1#"${repo_root}"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Map a path to the in-repo path whose rules apply to it, so every rule below is written once:
#   <anything>/vendor/modules/<name>/...  ->  modules/<name>/...            (vendored copy of a module)
#   <anything>/infra/terraform/<stack>/.. ->  <customer_stack_root>/<stack>/... (a customer stack)
# Paths inside this repo map to themselves, so a vendor/modules/ directory nested in this repo cannot borrow a module's exemption.
canon() {
  local p
  case "$1" in
    "${repo_root}"/*)
      rel "$1"
      return
      ;;
  esac
  p="/${1#/}"
  case "$p" in
    */vendor/modules/*) printf 'modules/%s\n' "${p##*/vendor/modules/}" ;;
    */infra/terraform/*) printf '%s/%s\n' "${customer_stack_root}" "${p##*/infra/terraform/}" ;;
    *) rel "$1" ;;
  esac
}

# Print the stack root (from tf_stack_roots) that contains the repo-relative path $1; fails when there is none.
stack_root_of() {
  local root
  for root in ${tf_stack_roots[@]+"${tf_stack_roots[@]}"}; do
    case "$1" in
      "${root}"/*)
        printf '%s\n' "$root"
        return 0
        ;;
    esac
  done
  return 1
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
  stack_dirs=()
  for root in ${tf_stack_roots[@]+"${tf_stack_roots[@]}"}; do
    stack_dirs+=("${repo_root}/${root}"/*)
  done
  for d in "${repo_root}"/modules/* "${repo_root}"/modules/*/examples/* ${stack_dirs[@]+"${stack_dirs[@]}"}; do
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

# Step 1b (--changed-since): keep only the directories a change can affect.
# Template stacks take modules from the registry, so a module change never reaches them; only local sources
# ("./" or "../") link directories, for example a module's examples and modules/alb/examples/https -> log-delivery.

# Files that no Terraform directory reads.
is_inert_path() {
  case "$1" in
    docs/* | *.md | LICENSE | release-please-config.json | .release-please-manifest.json) return 0 ;;
  esac
  return 1
}

# Print the repo-relative directories that the .tf files directly in directory $1 reference through local sources.
local_sources_of() {
  local s
  while IFS= read -r s; do
    [ -d "$1/$s" ] && rel "$(cd "$1/$s" && pwd)"
  done < <(awk '/^[[:space:]]*(#|\/\/)/ { next }
    match($0, /^[[:space:]]*source[[:space:]]*=[[:space:]]*"\.\.?\/[^"]*"/) {
      s = substr($0, RSTART, RLENGTH); sub(/^[^"]*"/, "", s); sub(/"$/, "", s); print s
    }' "$1"/*.tf)
  return 0
}

affected=""
# True when repo-relative directory $1 is one of the lines of $affected.
is_affected() {
  case $'\n'"${affected}" in *$'\n'"$1"$'\n'*) return 0 ;; esac
  return 1
}

select_changed_dirs() {
  local base files f r best kept=() d s tpl
  local dir_rels=()
  base="$(git -C "$repo_root" merge-base "$changed_since" HEAD)" || {
    echo "找不到 ${changed_since} 與 HEAD 的共同祖先（CI 的 checkout 需要 fetch-depth: 2）" >&2
    return 1
  }
  # Committed, uncommitted and untracked changes; --no-renames lists both sides of a move.
  files="$({
    git -C "$repo_root" diff --name-only --no-renames "$base"
    git -C "$repo_root" ls-files --others --exclude-standard
  } | sort -u)"
  for d in "${dirs[@]}"; do dir_rels+=("$(rel "$d")"); done

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    is_inert_path "$f" && continue
    # The deepest directory that contains the file owns it.
    best=""
    for r in "${dir_rels[@]}"; do
      case "$f" in "$r"/*) [ "${#r}" -gt "${#best}" ] && best="$r" ;; esac
    done
    if [ -n "$best" ]; then
      affected+="${best}"$'\n'
      continue
    fi
    case "$f" in
      modules/*) ;; # A deleted module leaves nothing to validate.
      templates/*/*)
        # A file outside every stack (stacks.sh, check-ssm-contract.sh, ...) affects all stacks of its template.
        tpl="${f#templates/}"
        tpl="templates/${tpl%%/*}/"
        for r in "${dir_rels[@]}"; do
          case "$r" in "$tpl"*) affected+="${r}"$'\n' ;; esac
        done
        ;;
      *)
        echo "== 變更範圍：${f} 是共用檔案，驗證全部目錄"
        return 0
        ;;
    esac
  done <<<"$files"

  for d in "${dirs[@]}"; do
    r="$(rel "$d")"
    if is_affected "$r"; then
      kept+=("$d")
      continue
    fi
    while IFS= read -r s; do
      if is_affected "$s"; then
        kept+=("$d")
        break
      fi
    done < <(local_sources_of "$d")
  done
  echo "== 變更範圍：${changed_since} 之後的變更影響 ${#kept[@]} / ${#dirs[@]} 個目錄"
  dirs=(${kept[@]+"${kept[@]}"})
}

if [ -n "$changed_since" ]; then
  select_changed_dirs || exit 1
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

# Print the local names in the required_providers blocks of the .tf files directly in directory $1.
required_providers_of() {
  local f
  for f in "$1"/*.tf; do
    [ -f "$f" ] || continue
    awk '/^[[:space:]]*(#|\/\/)/ { next }
      /required_providers[[:space:]]*\{/ { inblk = 1; depth = 0 }
      inblk {
        if (depth == 1 && match($0, /^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=/)) {
          n = substr($0, RSTART, RLENGTH); gsub(/[[:space:]=]/, "", n); print n
        }
        depth += gsub(/\{/, "{"); depth -= gsub(/\}/, "}")
        if (depth <= 0) inblk = 0
      }' "$f"
  done | sort -u
}

# S1: every test file declares a mock_provider for each provider in the required_providers of the directory it
# tests (the directory above tests/). Without required_providers the directory is assumed to use aws only.
for f in ${files_tftest[@]+"${files_tftest[@]}"}; do
  providers="$(required_providers_of "${f%/tests/*}")"
  [ -n "$providers" ] || providers=aws
  for p in $providers; do
    if ! grep -Eq "^[[:space:]]*mock_provider[[:space:]]+\"${p}\"" "$f"; then
      echo "S1 $(rel "$f"): 測試檔缺 mock_provider \"${p}\"（required_providers 有 ${p}）" >&2
      fail_static=1
    fi
  done
done

for f in ${files_tf[@]+"${files_tf[@]}"}; do
  r="$(canon "$f")"
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
      # S4: IAM only in iam-role (all types), iam-role-policy (aws_iam_role_policy only)
      # and iam-oidc-provider (aws_iam_openid_connect_provider only)
      case "$r" in
        modules/iam-role/*) ;;
        modules/iam-role-policy/*) scan_pattern S4 'modules/iam-role-policy 只允許 aws_iam_role_policy' "$f" '^[[:space:]]*resource[[:space:]]+"aws_iam_' '"aws_iam_role_policy"' ;;
        modules/iam-oidc-provider/*) scan_pattern S4 'modules/iam-oidc-provider 只允許 aws_iam_openid_connect_provider' "$f" '^[[:space:]]*resource[[:space:]]+"aws_iam_' '"aws_iam_openid_connect_provider"' ;;
        *) scan_pattern S4 'aws_iam_* 只能出現在 modules/iam-role、modules/iam-role-policy 與 modules/iam-oidc-provider' "$f" '^[[:space:]]*resource[[:space:]]+"aws_iam_' ;;
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
      # S9: no guardrail versions; once a version is published, apply only changes DRAFT and the plan stays clean
      scan_pattern S9 'aws_bedrock_guardrail_version 不得出現在 modules 與 templates（design 決策 46）' "$f" '^[[:space:]]*resource[[:space:]]+"aws_bedrock_guardrail_version"'
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
  if root="$(stack_root_of "$r")"; then
    stack="${r#"${root}"/}"
    scan_stack_resources "$f" "${stack%%/*}"
  fi
done

# S5: common.tf must be identical across the stacks of one template (templates may differ from each other);
# stacks outside this repo (customer repo) are compared with each other, not with the template,
# because their copy comes from another tag.
check_common_identical() {
  local f h first_common="" first_hash=""
  for f in "$@"; do
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
}
for root in ${tf_stack_roots[@]+"${tf_stack_roots[@]}"}; do
  check_common_identical "${repo_root}/${root}"/*/common.tf
done
outside_common=()
for f in ${files_tf[@]+"${files_tf[@]}"}; do
  case "$f" in "${repo_root}"/*) continue ;; esac
  [ "$(basename "$f")" = "common.tf" ] || continue
  case "$(canon "$f")" in "${customer_stack_root}"/*/common.tf) outside_common+=("$f") ;; esac
done
if [ "${#outside_common[@]}" -gt 0 ]; then check_common_identical "${outside_common[@]}"; fi

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

# S10: every provider block of a stack lock file needs at least 2 "h1:" hashes (darwin + linux).
# A lock written by init on macOS alone has only the darwin hash and fails in linux CI, which this machine cannot see.
# Customer stacks are judged the same way (their path maps to a template stack through canon()).
while IFS= read -r f; do
  c="$(canon "$(dirname "$f")")"
  case "$c" in "${customer_stack_root}"/*) ;; *) stack_root_of "$c" >/dev/null || continue ;; esac
  out="$(awk '
    /^provider[[:space:]]+"/ { name = $2; gsub(/"/, "", name); n = 0; inblk = 1; next }
    inblk && /^[[:space:]]*"h1:/ { n++ }
    inblk && /^}/ { if (n < 2) print name " (" n ")"; inblk = 0 }
  ' "$f")"
  if [ -n "$out" ]; then
    while IFS= read -r line; do
      echo "S10 $(rel "$f"): provider ${line} 的 h1: hash 少於 2 個（需要 darwin 與 linux 各一）；從已有兩個 h1: 的 lock 複製，不要在 macOS 上單獨 init 產生" >&2
    done <<<"$out"
    fail_static=1
  fi
done < <(for r in ${scan_roots[@]+"${scan_roots[@]}"}; do find "$r" -name '.terraform.lock.hcl' -not -path '*/.terraform/*' | sort; done)

# S11: every module README carries the BEGIN_TF_DOCS markers, and the input/output tables between them match terraform-docs.
# Always scans every module (README edits are inert for --changed-since). Only this repo's modules: vendored copies
# in a customer repo are not checked, and without .terraform-docs.yml (a customer checkout) the rule is skipped.
if [ -f "${repo_root}/.terraform-docs.yml" ]; then
  if ! command -v terraform-docs >/dev/null; then
    echo "S11 找不到 terraform-docs（需要 0.24.x）" >&2
    fail_static=1
  else
    for d in "${repo_root}"/modules/*/; do
      d="${d%/}"
      if ! grep -q '<!-- BEGIN_TF_DOCS -->' "$d/README.md" 2>/dev/null; then
        echo "S11 $(rel "$d")/README.md: 缺少 <!-- BEGIN_TF_DOCS --> 與 <!-- END_TF_DOCS -->；輸入／輸出表要由 terraform-docs 產生" >&2
        fail_static=1
        continue
      fi
      if ! terraform-docs -c "${repo_root}/.terraform-docs.yml" --output-check "$d" >/dev/null 2>&1; then
        echo "S11 $(rel "$d")/README.md: 輸入／輸出表跟程式碼不一致；執行 terraform-docs -c .terraform-docs.yml $(rel "$d") 重新產生" >&2
        fail_static=1
      fi
    done
  fi
fi

# Per template: the SSM contract check (when the template ships one) and its shell scripts (bash -n, shellcheck if installed).
have_shellcheck=1
command -v shellcheck >/dev/null || have_shellcheck=0
shellcheck_notice=0
for root in ${tf_stack_roots[@]+"${tf_stack_roots[@]}"}; do
  tpl="${root%/infra/terraform}"
  if [ -f "${repo_root}/${root}/check-ssm-contract.sh" ]; then
    if ! bash "${repo_root}/${root}/check-ssm-contract.sh"; then
      echo "FAIL ${root}/check-ssm-contract.sh 回傳非零" >&2
      fail_static=1
    fi
  fi
  while IFS= read -r f; do
    if ! bash -n "$f"; then
      echo "FAIL $(rel "$f"): bash -n 語法錯誤" >&2
      fail_static=1
    fi
    if [ "$have_shellcheck" -eq 1 ]; then
      shellcheck "$f" || fail_static=1
    elif [ "$shellcheck_notice" -eq 0 ]; then
      echo "略過 shellcheck：未安裝" >&2
      shellcheck_notice=1
    fi
  done < <(find "${repo_root}/${tpl}" -name '*.sh' -not -path '*/.terraform*' | sort)
done

# Local Helm charts shipped inside modules (modules/<name>/charts/<chart>): helm lint and helm template when helm is installed.
charts=()
for r in ${scan_roots[@]+"${scan_roots[@]}"}; do
  while IFS= read -r f; do charts+=("$(dirname "$f")"); done < <(find "$r" -path '*/charts/*' -name Chart.yaml -not -path '*/.terraform*' | sort)
done
if [ "${#charts[@]}" -gt 0 ]; then
  if command -v helm >/dev/null; then
    for c in "${charts[@]}"; do
      if ! helm lint "$c" >/dev/null || ! helm template "$c" >/dev/null; then
        echo "FAIL $(rel "$c"): helm lint 或 helm template 失敗" >&2
        fail_static=1
      fi
    done
  else
    echo "略過 helm lint：未安裝 helm（${#charts[@]} 個本地 chart）" >&2
  fi
fi

# Python code shipped inside modules (modules/<name>/lambda/): standard-library unittest when python3 is installed.
py_dirs=()
for r in ${scan_roots[@]+"${scan_roots[@]}"}; do
  while IFS= read -r d; do py_dirs+=("$d"); done < <(find "$r" -path '*/lambda/*' -name 'test_*.py' -not -path '*/.terraform*' -exec dirname {} \; | sort -u)
done
if [ "${#py_dirs[@]}" -gt 0 ]; then
  if command -v python3 >/dev/null; then
    for d in "${py_dirs[@]}"; do
      if ! python3 -I -m unittest discover -s "$d" -t "$d" -q; then
        echo "FAIL $(rel "$d"): python3 unittest 失敗" >&2
        fail_static=1
      fi
    done
  else
    echo "略過 python3 unittest：未安裝 python3" >&2
  fi
fi

if [ "$fail_static" -ne 0 ]; then
  echo "FAIL fmt 或靜態規則未過，不進入後面的驗證步驟" >&2
  exit 1
fi

if [ "${#dirs[@]}" -eq 0 ]; then
  echo "沒有找到要驗證的目錄"
  exit 0
fi

command -v tflint >/dev/null || { echo "找不到 tflint" >&2; exit 1; }

# The aws ruleset is a plugin; install it once (verified by tflint against GitHub attestations), then lint runs offline.
export TFLINT_PLUGIN_DIR="${TFLINT_PLUGIN_DIR:-${cache_root}/tflint-plugins}"
mkdir -p "${TFLINT_PLUGIN_DIR}"
tflint --init --config="${repo_root}/.tflint.hcl" >/dev/null || { echo "tflint --init 失敗：第一次要從 GitHub 下載 plugin，遇到額度限制時設定 GITHUB_TOKEN" >&2; exit 1; }

# Template stacks resolve modules from the registry; without a token init fails with a vague "Module not found".
for d in "${dirs[@]}"; do
  stack_root_of "$(rel "$d")" >/dev/null || continue
  if [ -z "${TF_TOKEN_app_terraform_io:-}" ] &&
    ! jq -e '.credentials["app.terraform.io"].token' "${HOME}/.terraform.d/credentials.tfrc.json" >/dev/null 2>&1; then
    echo "範本的 stack 從 app.terraform.io 抓 module，需要 token：先跑 terraform login，或設定 TF_TOKEN_app_terraform_io" >&2
    exit 1
  fi
  break
done

# Steps 4-7: init, validate, test, tflint for one directory.
validate_dir() {
  local dir="$1" r c data_dir lock=()
  r="$(rel "$dir")"
  c="$(canon "$dir")"
  data_dir="${cache_root}/tf-data/$(printf '%s' "$r" | sed 's|^/||; s|/|__|g')"
  export TF_DATA_DIR="$data_dir"
  case "$c" in
    *) stack_root_of "$c" >/dev/null && lock=(-lockfile=readonly) ;;
  esac

  echo "== ${r}"
  terraform -chdir="$dir" init -backend=false -input=false ${lock[@]+"${lock[@]}"} || return 1
  terraform -chdir="$dir" validate || return 1

  if [ -d "$dir/tests" ]; then
    terraform -chdir="$dir" test || return 1
  fi

  # Step 6b: static checks that terraform test cannot express (for example eks-addons install order via terraform graph).
  # Any executable tests/check-*.sh runs here; each must work offline after init -backend=false.
  for x in "$dir"/tests/check-*.sh; do
    [ -x "$x" ] || continue
    "$x" || return 1
  done

  # Step 6a: stacks (decided by directory layout, not by path) run tests against their tfvars files.
  local x
  for x in "$dir"/envs/*.tfvars; do
    [ -f "$x" ] && [ -d "$dir/tests/tfvars" ] || continue
    terraform -chdir="$dir" test -test-directory=tests/tfvars -var-file="envs/$(basename "$x")" || return 1
  done
  for x in "$dir"/envs/examples/*.tfvars; do
    [ -f "$x" ] && [ -d "$dir/tests/examples" ] || continue
    terraform -chdir="$dir" test -test-directory=tests/examples -var-file="envs/examples/$(basename "$x")" || return 1
  done

  # Module roots feed the README tables through terraform-docs, so their descriptions must not be empty;
  # examples and stacks are not documented that way.
  local doc_rules=()
  case "$c" in
    modules/*/*) ;;
    modules/*) doc_rules=(--enable-rule=terraform_documented_variables --enable-rule=terraform_documented_outputs) ;;
  esac
  tflint --chdir="$dir" --config="${repo_root}/.tflint.hcl" ${doc_rules[@]+"${doc_rules[@]}"} || return 1

  # Step 7a: stacks only call registry modules, so lint them expanded with each tfvars file to check the spec values.
  if stack_root_of "$c" >/dev/null; then
    for x in "$dir"/envs/*.tfvars "$dir"/envs/examples/*.tfvars; do
      [ -f "$x" ] || continue
      tflint --chdir="$dir" --config="${repo_root}/.tflint.hcl" --call-module-type=all --var-file="${x#"$dir"/}" || return 1
    done
  fi
}

for d in "${dirs[@]}"; do
  rc=0
  validate_dir "$d" || rc=1
  # Step 8: modules do not commit lock files; remove the one init created.
  case "$(canon "$d")" in
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
