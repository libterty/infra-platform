#!/usr/bin/env bash
# Run terraform for one stack, or for all of them in apply order, against one env.
# This is the only entry point: it picks the env files, the state location and the data directory together, so the
# four independent choices (AWS identity, backend, variables, data directory) cannot drift apart. See infra/README.md.
set -euo pipefail

# Apply order, on one line: check-ssm-contract.sh parses it from here. Destroy runs it backwards.
ORDER=(containerimage)

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<'USAGE'
用法：stacks.sh <env> <stack|all> <init|validate|plan|apply|destroy|output> [--yes] [--dry-run] [-- <terraform 參數>...]

  <stack|all>  單一 stack，或依 ORDER 跑全部（destroy 反向）
  --yes        apply、destroy 加 -auto-approve，不再詢問
  --dry-run    只印出會執行的指令，不執行 terraform
  --           其後的參數原樣交給 terraform（validate、init 不接受）
USAGE
}

die() {
  echo "錯誤：$*" >&2
  exit 2
}

in_order() {
  local s
  for s in "${ORDER[@]}"; do
    [ "$s" = "$1" ] && return 0
  done
  return 1
}

if [ "$#" -lt 3 ]; then
  usage
  exit 2
fi
env_name="$1"
target="$2"
action="$3"
shift 3

yes=0
dry_run=0
extra=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes) yes=1 ;;
    --dry-run) dry_run=1 ;;
    --)
      shift
      extra=("$@")
      break
      ;;
    *) die "不認得的參數：$1" ;;
  esac
  shift
done

[[ "$env_name" =~ ^[a-z][a-z0-9]{1,11}$ ]] || die "env 格式不對：${env_name}"
case "$action" in
  init | validate | plan | apply | destroy | output) ;;
  *) die "不認得的動作：${action}（可用 init validate plan apply destroy output）" ;;
esac
if [ "${#extra[@]}" -gt 0 ] && { [ "$action" = init ] || [ "$action" = validate ]; }; then
  die "${action} 不接受 -- 之後的 terraform 參數"
fi

selected=()
if [ "$target" = "all" ]; then
  selected=("${ORDER[@]}")
  if [ "$action" = destroy ]; then
    reversed=()
    for ((i = ${#selected[@]} - 1; i >= 0; i--)); do reversed+=("${selected[$i]}"); done
    selected=("${reversed[@]}")
  fi
else
  in_order "$target" || die "不認得的 stack：${target}（可用 ${ORDER[*]}）"
  selected=("$target")
fi

# Every selected stack must have this env's files before anything runs, so `all` does not stop halfway.
for s in "${selected[@]}"; do
  [ -f "${here}/${s}/envs/${env_name}.tfvars" ] || die "找不到 ${s}/envs/${env_name}.tfvars"
  if [ "$action" = init ]; then
    [ -f "${here}/${s}/envs/${env_name}.tfbackend" ] || die "找不到 ${s}/envs/${env_name}.tfbackend"
  fi
done

# Run terraform in the current directory, or only print the command with --dry-run.
tf() {
  if [ "$dry_run" -eq 1 ]; then
    printf '+ terraform'
    printf ' %q' "$@"
    printf '\n'
  else
    terraform "$@"
  fi
}

run_stack() {
  local stack="$1" data_dir=".terraform-${env_name}"
  local var_file="-var-file=envs/${env_name}.tfvars"
  local approve=()
  [ "$yes" -eq 1 ] && approve=(-auto-approve)
  # validate must not overwrite the backend settings a real init left in the env's data directory.
  [ "$action" = validate ] && data_dir=".terraform-${env_name}-validate"

  echo "== ${stack}"
  if [ "$dry_run" -eq 1 ]; then
    echo "+ cd ${stack} && export TF_DATA_DIR=${data_dir}"
  fi
  cd "${here}/${stack}"
  export TF_DATA_DIR="$data_dir"

  case "$action" in
    init) tf init -reconfigure -input=false "-backend-config=envs/${env_name}.tfbackend" ;;
    validate)
      tf init -reconfigure -backend=false -input=false -lockfile=readonly
      tf validate
      ;;
    plan) tf plan "$var_file" ${extra[@]+"${extra[@]}"} ;;
    apply) tf apply "$var_file" ${approve[@]+"${approve[@]}"} ${extra[@]+"${extra[@]}"} ;;
    destroy) tf destroy "$var_file" ${approve[@]+"${approve[@]}"} ${extra[@]+"${extra[@]}"} ;;
    output) tf output ${extra[@]+"${extra[@]}"} ;;
  esac
}

for s in "${selected[@]}"; do
  (run_stack "$s")
done
