#!/usr/bin/env bash
# Run example6 end to end against Floci, a local AWS emulator, without touching a real account.
# The template is never modified: it is copied outside the repo, each stack gets a provider override and a backend
# file that point at Floci, and the copy's own stacks.sh runs in ORDER. See README.md for what this proves and what not.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template_tf="$(cd "${here}/../terraform" && pwd)"

FLOCI_IMAGE="${FLOCI_IMAGE:-docker.io/floci/floci:2.4.0}"
FLOCI_CONTAINER="${FLOCI_CONTAINER:-floci-example6}"
FLOCI_NETWORK="${FLOCI_NETWORK:-floci-net}"
FLOCI_PORT="${FLOCI_PORT:-4566}"
# Outside the repo: validate.sh scans every .tf under templates/.
tmp_root="${TMPDIR:-/tmp}"
WORK_DIR="${FLOCI_WORK_DIR:-${tmp_root%/}/floci-example6}"
ENV_NAME=dev
REGION=ap-northeast-1
ACCOUNT_ID=111111111111
PROJECT=example
# api/envs/dev.tfvars and web/envs/dev.tfvars: origin_verify_header_name.
ORIGIN_HEADER=X-Origin-Verify
STATE_BUCKET=example-dev-tfstate-floci
# localhost, not 127.0.0.1: S3 Control prefixes the account ID to the host, and <account>.localhost still resolves
# to loopback while <account>.127.0.0.1 does not.
endpoint="http://localhost:${FLOCI_PORT}"
work_tf="${WORK_DIR}/terraform"

usage() {
  cat >&2 <<'USAGE'
用法：floci.sh <run|up|prepare|init|apply|verify|destroy|down>

  run      up → prepare → init → apply → verify → destroy，一次跑完（預設）
  up       啟動 Floci container（已在跑就沿用）
  prepare  把 example6 複製到 FLOCI_WORK_DIR，換上指向 Floci 的 provider 與 backend，建 state bucket
  init     複本的 stacks.sh dev all init
  apply    先 apply containerimage、推測試用映像，再依 ORDER apply 全部
  verify   每個 stack 再 plan 一次要沒有變更，並檢查 SSM 參數與 API 回應
  destroy  依 ORDER 反向 destroy
  down     移除 Floci container
USAGE
}

die() {
  echo "錯誤：$*" >&2
  exit 2
}

log() { echo "== $*"; }

# Docker if present, otherwise Podman. Floci starts Lambda containers through this runtime's socket.
runtime() {
  if command -v docker >/dev/null 2>&1; then
    echo docker
  elif command -v podman >/dev/null 2>&1; then
    echo podman
  else
    die "找不到 docker 或 podman"
  fi
}

# The socket path as the runtime's daemon sees it (inside the VM for Podman machine).
runtime_socket() {
  if [ "$(runtime)" = podman ]; then
    local s
    s="$(podman info --format '{{.Host.RemoteSocket.Path}}')"
    echo "${s#unix://}"
  else
    echo /var/run/docker.sock
  fi
}

# Every AWS call from here goes to Floci with fake keys; a real profile in the caller's shell is dropped.
floci_env() {
  unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_SESSION_TOKEN AWS_SECURITY_TOKEN AWS_VAULT AWS_ROLE_ARN \
    AWS_WEB_IDENTITY_TOKEN_FILE AWS_CONFIG_FILE AWS_SHARED_CREDENTIALS_FILE
  export AWS_ENDPOINT_URL="$endpoint"
  export AWS_ACCESS_KEY_ID="$ACCOUNT_ID"
  export AWS_SECRET_ACCESS_KEY=floci
  export AWS_REGION="$REGION"
  export AWS_DEFAULT_REGION="$REGION"
  export AWS_PAGER=""
}

awsl() { aws --endpoint-url "$endpoint" "$@"; }

stacks() { "${work_tf}/stacks.sh" "$ENV_NAME" "$@"; }

require_work() {
  [ -x "${work_tf}/stacks.sh" ] || die "還沒 prepare：找不到 ${work_tf}/stacks.sh"
}

# Podman refuses plain HTTP to localhost:<port>, so Floci cannot pull the API image from its own registry. The
# fallback, an image tagged with the AWS registry name, is worse: Floci still pulls it and reaches the real ECR.
podman_registry_check() {
  # shellcheck disable=SC2088 # the tilde is expanded inside the VM
  local conf='~/.config/containers/registries.conf.d/floci.conf'
  [ "$(uname -s)" = Darwin ] || return 0
  # shellcheck disable=SC2016 # expanded inside the VM
  if ! podman machine ssh "grep -qx 'location = \"localhost:${FLOCI_PORT}\"' ${conf}" 2>/dev/null; then
    cat >&2 <<EOF
錯誤：Podman 還不允許用 HTTP 連 localhost:${FLOCI_PORT}，Floci 的 ECR 拉不到映像。先跑一次：
  podman machine ssh 'mkdir -p ~/.config/containers/registries.conf.d && printf "[[registry]]\\nlocation = \\"localhost:${FLOCI_PORT}\\"\\ninsecure = true\\n" > ${conf}'
EOF
    exit 2
  fi
}

cmd_up() {
  local rt
  rt="$(runtime)"
  [ "$rt" != podman ] || podman_registry_check
  if [ "$("$rt" ps -q --filter "name=^${FLOCI_CONTAINER}$")" != "" ]; then
    log "Floci 已在跑：${FLOCI_CONTAINER}"
  else
    "$rt" rm -f "$FLOCI_CONTAINER" >/dev/null 2>&1 || true
    "$rt" network exists "$FLOCI_NETWORK" 2>/dev/null || "$rt" network create "$FLOCI_NETWORK" >/dev/null
    log "啟動 ${FLOCI_IMAGE}"
    "$rt" run -d --name "$FLOCI_CONTAINER" --network "$FLOCI_NETWORK" \
      -p "127.0.0.1:${FLOCI_PORT}:4566" \
      -v "$(runtime_socket):/var/run/docker.sock" \
      --security-opt label=disable \
      -e FLOCI_SERVICES_LAMBDA_DOCKER_NETWORK="$FLOCI_NETWORK" \
      -e FLOCI_DEFAULT_ACCOUNT_ID="$ACCOUNT_ID" \
      "$FLOCI_IMAGE" >/dev/null
  fi
  floci_env
  local _
  for _ in $(seq 1 30); do
    if awsl sts get-caller-identity --query Account --output text 2>/dev/null | grep -qx "$ACCOUNT_ID"; then
      log "Floci 就緒，帳號 ${ACCOUNT_ID}"
      return 0
    fi
    sleep 1
  done
  die "Floci 30 秒內沒有回應：${endpoint}"
}

# The backend file keeps each stack's real state key; only the location and credentials change.
write_backend() {
  local stack="$1" key
  key="$(sed -n 's/^key *= *"\(.*\)"$/\1/p' "${template_tf}/${stack}/envs/${ENV_NAME}.tfbackend")"
  [ -n "$key" ] || die "${stack}/envs/${ENV_NAME}.tfbackend 沒有 key"
  cat >"${work_tf}/${stack}/envs/${ENV_NAME}.tfbackend" <<EOF
# Generated by floci.sh for the local emulator; the template's own file is untouched.
bucket                      = "${STATE_BUCKET}"
key                         = "${key}"
region                      = "${REGION}"
use_lockfile                = true
use_path_style              = true
endpoints                   = { s3 = "${endpoint}" }
access_key                  = "${ACCOUNT_ID}"
secret_key                  = "floci"
skip_credentials_validation = true
skip_requesting_account_id  = true
skip_metadata_api_check     = true
skip_region_validation      = true
EOF
}

# Files removed from the copy because Floci cannot create what they declare; README.md lists them as not covered.
# Format: <stack>/<file>|<reason>
SKIPPED_FILES=(
  "web/logs.tf|Floci ${FLOCI_IMAGE##*:} 不支援 CloudWatch Logs delivery（PutDeliveryDestination 回 UnsupportedOperation）"
)

# Second-plan diffs that come from Floci's responses, checked against the API on Floci 2.4.0; any other diff fails.
# Format: <stack>|<resource address>|<reason>
KNOWN_DRIFT=(
  "api|module.function.aws_lambda_function.this|GetFunction 在沒設定時仍回空的 ImageConfig（AWS 會省略）"
  "web|module.cdn.aws_cloudfront_distribution.this|distribution 不保存 WebACLId，讀回來是 null"
  "web|module.cdn.aws_cloudfront_function.spa_fallback[0]|CloudFront function 不保存 tag"
)

order() {
  # The same line check-ssm-contract.sh parses.
  sed -n 's/^ORDER=(\(.*\))$/\1/p' "${template_tf}/stacks.sh"
}

# Floci's ECR returns <account>.dkr.ecr.<region>.localhost:<port>/<repo>, which lambda-function's image_uri
# validation (real ECR hosts only) rejects. Floci rewrites an amazonaws.com image URI to its own registry when the
# function pulls, so the copy, and only the copy, turns the host back into the AWS one.
patch_image_uri() {
  local f="${work_tf}/api/function.tf"
  # shellcheck disable=SC2016 # Terraform interpolation, matched literally.
  local from='"${module.in.strings["api_repository_url"]}:${var.api_image_tag}"'
  local to="\"\${replace(module.in.strings[\"api_repository_url\"], \".localhost:${FLOCI_PORT}/\", \".amazonaws.com/\")}:\${var.api_image_tag}\""
  [ "$(grep -cF "$from" "$f")" -eq 1 ] || die "api/function.tf 的 image_uri 寫法變了，floci.sh 要跟著改"
  FROM="$from" TO="$to" perl -0pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/' "$f"
}

cmd_prepare() {
  floci_env
  log "複製 example6 到 ${WORK_DIR}"
  rm -rf "$work_tf"
  mkdir -p "$WORK_DIR"
  rsync -a --exclude '.terraform/' --exclude '.terraform-*/' "${template_tf}/" "${work_tf}/"
  local s
  for s in $(order); do
    cp "${here}/provider_override.tf.tmpl" "${work_tf}/${s}/floci_override.tf"
    write_backend "$s"
  done
  patch_image_uri
  local entry
  for entry in "${SKIPPED_FILES[@]}"; do
    rm "${work_tf}/${entry%%|*}"
    echo "  略過 ${entry%%|*}：${entry#*|}"
  done
  if ! awsl s3api head-bucket --bucket "$STATE_BUCKET" >/dev/null 2>&1; then
    log "建立 state bucket ${STATE_BUCKET}"
    awsl s3api create-bucket --bucket "$STATE_BUCKET" \
      --create-bucket-configuration "LocationConstraint=${REGION}" >/dev/null
  fi
}

cmd_init() {
  require_work
  floci_env
  stacks all init
}

push_stub_image() {
  local rt repo tag image
  rt="$(runtime)"
  repo="$(cd "${work_tf}/containerimage" && TF_DATA_DIR=".terraform-${ENV_NAME}" terraform output -raw api_repository_url)"
  tag="$(sed -n 's/^api_image_tag *= *"\(.*\)"$/\1/p' "${work_tf}/api/envs/${ENV_NAME}.tfvars")"
  if [ -z "$repo" ] || [ -z "$tag" ]; then
    die "拿不到 repository URL 或 api_image_tag"
  fi
  image="${repo}:${tag}"
  # An image under the AWS registry name makes Floci pull from the real ECR instead of its own registry.
  if "$rt" image inspect "${image/.localhost:${FLOCI_PORT}\//.amazonaws.com/}" >/dev/null 2>&1; then
    die "本機有用 AWS registry 名稱命名的 ${repo##*/} 映像，Floci 會去真的 ECR 拉；先 ${rt} rmi 它"
  fi
  log "建置測試用映像 ${image}"
  # api/function.tf declares arm64; without --platform a cached amd64 base image would be reused.
  "$rt" build -q --platform linux/arm64 -t "$image" "${here}/lambda-stub" >/dev/null
  # The repository's tags are immutable, as on AWS: a tag that is already there is not pushed again.
  if awsl ecr describe-images --repository-name "${repo##*/}" --image-ids "imageTag=${tag}" >/dev/null 2>&1; then
    echo "  ${tag} 已在 repository 裡（tag 不可覆寫），不再推送"
  elif [ "$rt" = podman ]; then
    "$rt" push -q --tls-verify=false "$image"
  else
    "$rt" push -q "$image"
  fi
}

# REFERENCE.md step 3: the value goes into the origin verify secret once, then web reads it back from there.
origin_secret_arn() {
  awsl ssm get-parameter --name "/${PROJECT}/${ENV_NAME}/foundation/origin_verify_secret_arn" \
    --query Parameter.Value --output text
}

seed_origin_verify() {
  local arn
  arn="$(origin_secret_arn)"
  # Floci gives CreateSecret an empty version even without a value (AWS creates none), so test the value itself.
  local current
  current="$(awsl secretsmanager get-secret-value --secret-id "$arn" --query SecretString --output text 2>/dev/null || true)"
  if [ "${#current}" -lt 16 ] || [ "$current" = None ]; then
    log "寫入 origin verify 的值"
    openssl rand -hex 24 | tr -d '\n' |
      awsl secretsmanager put-secret-value --secret-id "$arn" --secret-string file:///dev/stdin >/dev/null
  fi
}

load_origin_verify() {
  TF_VAR_origin_verify_header_value="$(awsl secretsmanager get-secret-value --secret-id "$(origin_secret_arn)" \
    --query SecretString --output text)"
  export TF_VAR_origin_verify_header_value
}

cmd_apply() {
  require_work
  floci_env
  stacks containerimage apply --yes
  stacks foundation apply --yes
  seed_origin_verify
  load_origin_verify
  push_stub_image
  stacks all apply --yes
}

# only_known_drift <stack> <plan log>: true when every resource the plan changes is listed in KNOWN_DRIFT.
only_known_drift() {
  local stack="$1" planlog="$2" addr entry known
  while IFS= read -r addr; do
    known=0
    for entry in "${KNOWN_DRIFT[@]}"; do
      if [ "${entry%%|*}" = "$stack" ] && [ "$(echo "$entry" | cut -d'|' -f2)" = "$addr" ]; then
        known=1
        echo "    ${addr}：$(echo "$entry" | cut -d'|' -f3-)"
      fi
    done
    [ "$known" -eq 1 ] || return 1
  done < <(sed 's/\x1b\[[0-9;]*m//g' "$planlog" | sed -n 's/^  # \(.*\) will be .*$/\1/p; s/^  # \(.*\) must be .*$/\1/p')
}

# The stage URL Terraform reports is the AWS one. Requests always go to Floci on localhost, with the API's host in
# the Host header (Floci routes execute-api by host); nothing here ever connects to amazonaws.com.
# expect_status <code> <label> <api endpoint> <path> [curl args...]: print the result, return 1 on a different status.
expect_status() {
  local want="$1" label="$2" api="$3" path="$4" host got body
  shift 4
  host="${api#https://}"
  host="${host%%/*}"
  case "$host" in
    *.execute-api.*.amazonaws.com) host="${host%.amazonaws.com}.localhost:${FLOCI_PORT}" ;;
    *) die "看不懂的 API endpoint：${api}" ;;
  esac
  body="$(mktemp)"
  got="$(curl -s -o "$body" -w '%{http_code}' -H "Host: ${host}" "$@" "${endpoint}${path}" || true)"
  echo "  ${label} → ${got}（要 ${want}）$(head -c 200 "$body")"
  rm -f "$body"
  [ "$got" = "$want" ]
}

cmd_verify() {
  require_work
  floci_env
  load_origin_verify
  local failed=0 s rc
  log "每個 stack 再 plan 一次：要沒有變更"
  for s in $(order); do
    rc=0
    stacks "$s" plan -- -detailed-exitcode -input=false >"${WORK_DIR}/plan-${s}.log" 2>&1 || rc=$?
    case "$rc" in
      0) echo "  ${s}: 沒有變更" ;;
      2)
        if only_known_drift "$s" "${WORK_DIR}/plan-${s}.log"; then
          echo "  ${s}: 只有已知的 Floci 差異"
        else
          echo "  ${s}: 有變更（${WORK_DIR}/plan-${s}.log）"
          failed=1
        fi
        ;;
      *)
        echo "  ${s}: plan 失敗（${WORK_DIR}/plan-${s}.log）"
        failed=1
        ;;
    esac
  done

  log "SSM 參數（跨 stack 契約）"
  awsl ssm get-parameters-by-path --path "/${PROJECT}/${ENV_NAME}" --recursive --query 'Parameters[].Name' \
    --output text | tr '\t' '\n' | sort | sed 's/^/  /'

  local api
  api="$(cd "${work_tf}/api" && TF_DATA_DIR=".terraform-${ENV_NAME}" terraform output -raw api_endpoint)"
  log "API：${api}"
  expect_status 403 "GET /api/health 沒帶 origin verify header" "$api" /api/health || failed=1
  expect_status 200 "GET /api/health 帶 origin verify header" "$api" /api/health \
    -H "${ORIGIN_HEADER}: ${TF_VAR_origin_verify_header_value}" || failed=1
  expect_status 401 "GET /api/items 沒帶 token" "$api" /api/items \
    -H "${ORIGIN_HEADER}: ${TF_VAR_origin_verify_header_value}" || failed=1

  if [ "$failed" -eq 0 ]; then log "verify 全部通過"; else log "verify 有項目沒通過"; fi
  return "$failed"
}

# REFERENCE.md〈destroy〉: the repository has force_delete = false, so it is emptied first.
empty_repository() {
  local repo ids d
  local -a digests image_ids=()
  # From the resource in state: after a destroy that stopped here, the outputs and the SSM parameter are gone.
  repo="$(cd "${work_tf}/containerimage" && TF_DATA_DIR=".terraform-${ENV_NAME}" \
    terraform state show -no-color module.api_repository.aws_ecr_repository.this 2>/dev/null |
    sed -n 's/^ *name *= *"\(.*\)"$/\1/p')" || true
  [ -n "$repo" ] || return 0
  ids="$(awsl ecr list-images --repository-name "$repo" --query 'imageIds[].imageDigest' --output text)"
  if [ -z "$ids" ] || [ "$ids" = None ]; then
    return 0
  fi
  log "清空 ECR repository ${repo}"
  read -ra digests <<<"$ids"
  for d in "${digests[@]}"; do image_ids+=("imageDigest=${d}"); done
  awsl ecr batch-delete-image --repository-name "$repo" --image-ids "${image_ids[@]}" >/dev/null
}

cmd_destroy() {
  require_work
  floci_env
  # web needs a value that passes validation even when foundation (and the secret) is already gone after a partial
  # destroy; destroy does not use it for anything else.
  load_origin_verify 2>/dev/null || export TF_VAR_origin_verify_header_value=destroy-only-placeholder-value
  empty_repository
  stacks all destroy --yes
}

# Floci keeps the ECR registry (and any Lambda container) as labelled sibling containers with a data volume, which
# outlive the emulator's in-memory state; leaving them makes the next run find repositories its state never created.
cmd_down() {
  local rt ids
  rt="$(runtime)"
  "$rt" rm -f "$FLOCI_CONTAINER" >/dev/null 2>&1 || true
  ids="$("$rt" ps -aq --filter label=floci=true)"
  # shellcheck disable=SC2086 # one ID per word
  [ -z "$ids" ] || "$rt" rm -f $ids >/dev/null
  ids="$("$rt" volume ls -q --filter label=floci=true)"
  # shellcheck disable=SC2086 # one name per word
  [ -z "$ids" ] || "$rt" volume rm -f $ids >/dev/null
  log "已移除 ${FLOCI_CONTAINER} 與 Floci 啟動的 container、volume"
}

cmd_run() {
  cmd_up
  cmd_prepare
  cmd_init
  cmd_apply
  local rc=0
  cmd_verify || rc=$?
  cmd_destroy
  return "$rc"
}

action="${1:-run}"
case "$action" in
  run | up | prepare | init | apply | verify | destroy | down) "cmd_${action}" ;;
  -h | --help | help) usage ;;
  *)
    usage
    exit 2
    ;;
esac
