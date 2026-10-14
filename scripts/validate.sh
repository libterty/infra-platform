#!/usr/bin/env bash
# 離線驗證：fmt、init -backend=false、validate、test（mock）、tflint 與靜態規則。不碰雲端。
# 用法：scripts/validate.sh [目錄...]   沒給參數時掃 modules 與 templates。
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache_root="${repo_root}/.cache"
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-${cache_root}/plugins}"
mkdir -p "${TF_PLUGIN_CACHE_DIR}"
# module 沒有 lock 檔，不開這個旗標的話 terraform 不用快取、每個目錄重新下載 provider。
# 範本 stack 仍以 -lockfile=readonly 核對 lock 檔的 checksum。
export TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true

# 步驟 0：第二道防線。測試漏寫 mock_provider 時要失敗，而不是拿到本機的 aws-vault session。
for v in $(env | sed -n 's/^\(AWS_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export AWS_CONFIG_FILE=/dev/null
export AWS_SHARED_CREDENTIALS_FILE=/dev/null
export AWS_EC2_METADATA_DISABLED=true

tf_stack_glob="templates/project-infra/infra/terraform"

command -v terraform >/dev/null || { echo "找不到 terraform" >&2; exit 1; }

# 回傳相對 repo_root 的路徑；repo 外的路徑原樣回傳。
rel() {
  case "$1" in
    "${repo_root}"/*) printf '%s\n' "${1#"${repo_root}"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# 步驟 1：找目錄。不能從 repo 根目錄掃：docs/slides/ 有 .tf，本機存在、CI 不存在。
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

# 步驟 2：fmt。失敗不中斷，繼續跑靜態規則，一次列出全部問題。
if [ "${#scan_roots[@]}" -gt 0 ]; then
  echo "== fmt"
  if ! terraform fmt -check -recursive "${scan_roots[@]}"; then
    echo "FAIL fmt：上面列出的檔案格式不符，執行 terraform fmt 修正" >&2
    fail_static=1
  fi
fi

# 步驟 3：靜態規則。
# 每條規則印 "S<n> <相對路徑>[:行號]: 說明"。S5 一律掃整個 repo 的範本，其餘只掃 scan_roots。
echo "== 靜態規則"
files_tf=()
files_tftest=()
files_tfbackend=()
for r in ${scan_roots[@]+"${scan_roots[@]}"}; do
  while IFS= read -r f; do files_tf+=("$f"); done < <(find "$r" -name '*.tf' -not -path '*/.terraform*' | sort)
  while IFS= read -r f; do files_tftest+=("$f"); done < <(find "$r" -name '*.tftest.hcl' -not -path '*/.terraform*' | sort)
  while IFS= read -r f; do files_tfbackend+=("$f"); done < <(find "$r" -name '*.tfbackend' -not -path '*/.terraform*' | sort)
done

# 印出 awk 找到的違規行；有輸出就算失敗。$1=規則編號、$2=說明、$3=檔案、$4=awk 模式
scan_pattern() {
  local out
  out="$(awk -v pat="$4" '/^[[:space:]]*(#|\/\/)/ { next } $0 ~ pat { print FNR ": " $0 }' "$3")"
  if [ -n "$out" ]; then
    while IFS= read -r line; do echo "$1 $(rel "$3"):${line}  <- $2" >&2; done <<<"$out"
    fail_static=1
  fi
}

# S1：每個測試檔都要宣告 mock_provider "aws"
for f in ${files_tftest[@]+"${files_tftest[@]}"}; do
  if ! grep -Eq '^[[:space:]]*mock_provider[[:space:]]+"aws"' "$f"; then
    echo "S1 $(rel "$f"): 測試檔缺 mock_provider \"aws\"" >&2
    fail_static=1
  fi
done

for f in ${files_tf[@]+"${files_tf[@]}"}; do
  r="$(rel "$f")"
  # S2：aws_ssm_parameter 只能出現在 modules/ssm-publish/
  case "$r" in
    modules/ssm-publish/*) ;;
    *) scan_pattern S2 'aws_ssm_parameter 只能由 modules/ssm-publish 宣告' "$f" '^[[:space:]]*resource[[:space:]]+"aws_ssm_parameter"' ;;
  esac
  # S3：範本的 ssm-inputs.tf 不得讀 .value
  case "$r" in
    templates/*/ssm-inputs.tf) scan_pattern S3 'ssm-inputs.tf 只能讀 insecure_value' "$f" '[.]value([^A-Za-z0-9_]|$)' ;;
  esac
  case "$r" in
    modules/*)
      # S4：module 不建 IAM；security group 只有 vpc 可以
      scan_pattern S4 'module 不得宣告 aws_iam_* 資源' "$f" '^[[:space:]]*resource[[:space:]]+"aws_iam_'
      case "$r" in
        modules/vpc/*) ;;
        *) scan_pattern S4 'aws_security_group* 只能出現在 modules/vpc' "$f" '^[[:space:]]*resource[[:space:]]+"aws_security_group' ;;
      esac
      # S7：module 不得出現 random_password
      scan_pattern S7 'modules 不得使用 random_password' "$f" 'random_password'
      ;;
  esac
  # S7：rds 不得宣告含 password 的變數
  if [ "$r" = "modules/rds/variables.tf" ]; then
    scan_pattern S7 'rds 不得宣告含 password 的變數' "$f" '^[[:space:]]*variable[[:space:]]+"[^"]*[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][^"]*"'
  fi
done

# S5：範本各 stack 的 common.tf 雜湊必須相同
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

# S6：tfbackend 的 key 要等於 <project>-<env>/<stack>/terraform.tfstate；envs/examples/ 不得有 tfbackend
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

# 步驟 4-7：單一目錄的初始化、validate、test、tflint。
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

  # 6a：範本 stack 對 tfvars 檔本身跑測試。
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
  # 步驟 8：module 不提交 lock 檔，初始化產生的要清掉。
  case "$(rel "$d")" in
    modules/*) rm -f "$d/.terraform.lock.hcl" ;;
  esac
  if [ "$rc" -ne 0 ]; then
    failed+=("$(rel "$d")")
  fi
done

# 步驟 9：彙整。
if [ "${#failed[@]}" -gt 0 ]; then
  echo "" >&2
  echo "FAIL 以下目錄未通過：" >&2
  printf '  %s\n' "${failed[@]}" >&2
  exit 1
fi
echo "OK：${#dirs[@]} 個目錄全部通過"
