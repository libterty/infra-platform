#!/usr/bin/env bash
# Run example2 end to end against Floci, a local AWS emulator, without touching a real account.
# The template is never modified: it is copied outside the repo, each stack gets a provider override and a backend
# file that point at Floci, and the copy's own stacks.sh runs in ORDER. See README.md for what this proves and what not.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template_tf="$(cd "${here}/../terraform" && pwd)"

FLOCI_IMAGE="${FLOCI_IMAGE:-docker.io/floci/floci:2.4.0}"
FLOCI_CONTAINER="${FLOCI_CONTAINER:-floci-example2}"
FLOCI_NETWORK="${FLOCI_NETWORK:-floci-net}"
FLOCI_PORT="${FLOCI_PORT:-4566}"
# The ALB's HTTPS listener (443 inside Floci) on the host, for trace.
ALB_PORT="${ALB_PORT:-8443}"
# Outside the repo: validate.sh scans every .tf under templates/.
tmp_root="${TMPDIR:-/tmp}"
WORK_DIR="${FLOCI_WORK_DIR:-${tmp_root%/}/floci-example2}"
ENV_NAME=dev
REGION=ap-northeast-1
ACCOUNT_ID=111111111111
PROJECT=example
STATE_BUCKET=example-dev-tfstate-floci
# loadbalancer/envs/dev.tfvars: origin_verify_header_name and origin_verify_host_headers.
ORIGIN_HEADER=X-Origin-Verify
API_HOST=api.dev.example.com
# localhost, not 127.0.0.1: S3 Control prefixes the account ID to the host, and <account>.localhost still resolves
# to loopback while <account>.127.0.0.1 does not.
endpoint="http://localhost:${FLOCI_PORT}"
work_tf="${WORK_DIR}/terraform"

usage() {
  cat >&2 <<'USAGE'
用法：floci.sh <run|up|prepare|init|apply|verify|status|trace|destroy|down>

  run      up → prepare → init → apply → verify → destroy，一次跑完（預設）
  up       啟動 Floci container（已在跑就沿用）
  prepare  把 example2 複製到 FLOCI_WORK_DIR，換上指向 Floci 的 provider 與 backend，建 state bucket
  init     複本的 stacks.sh dev all init
  apply    先 apply containerimage、推測試用映像，再依 ORDER apply 全部
  verify   每個 stack 再 plan 一次要沒有變更，列出 SSM 參數，再跑 trace
  status   列出各 stack 建了哪些 AWS 資源、Floci 起了哪些 container、ECS task 與 ALB target 的狀態
  trace    從 ALB 送一個請求進來，印出 api 經過的每一跳（資料庫、Redis、AgentCore）
  destroy  依 ORDER 反向 destroy
  down     移除 Floci 和它啟動的 container、volume
USAGE
}

die() {
  echo "錯誤：$*" >&2
  exit 2
}

log() { echo "== $*"; }

# Docker if present, otherwise Podman. Floci starts ECS tasks, Lambda, RDS and Redis containers through its socket.
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
  # One provider download shared by every stack (and every Floci harness) instead of a copy per stack.
  export TF_PLUGIN_CACHE_DIR="${FLOCI_PLUGIN_CACHE:-${tmp_root%/}/floci-terraform-plugin-cache}"
  mkdir -p "$TF_PLUGIN_CACHE_DIR"
}

awsl() { aws --endpoint-url "$endpoint" "$@"; }

stacks() { "${work_tf}/stacks.sh" "$ENV_NAME" "$@"; }

tf_in() {
  local stack="$1"
  shift
  (cd "${work_tf}/${stack}" && TF_DATA_DIR=".terraform-${ENV_NAME}" terraform "$@")
}

require_work() {
  [ -x "${work_tf}/stacks.sh" ] || die "還沒 prepare：找不到 ${work_tf}/stacks.sh"
}

# Podman needs two settings inside its VM:
# - plain HTTP to localhost:<port>, so Floci can pull the test images from its own ECR;
# - the fake account's real ECR hosts blocked. The modules only take AWS-shaped image URIs, which Floci rewrites to
#   its own registry; if that rewrite ever does not happen, Podman refuses the pull instead of reaching AWS.
podman_registry_check() {
  [ "$(uname -s)" = Darwin ] || return 0
  # shellcheck disable=SC2088 # the tilde is expanded inside the VM
  local dir='~/.config/containers/registries.conf.d'
  local ok=1
  # shellcheck disable=SC2016 # expanded inside the VM
  podman machine ssh "grep -qx 'location = \"localhost:${FLOCI_PORT}\"' ${dir}/floci.conf" 2>/dev/null || ok=0
  podman machine ssh "grep -q '${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com' ${dir}/floci-block-ecr.conf" \
    2>/dev/null || ok=0
  [ "$ok" -eq 1 ] && return 0
  cat >&2 <<EOF
錯誤：Podman 還沒設定好。先跑下面兩個指令，再重啟 Podman API（podman machine ssh systemctl --user restart podman.service）：
  podman machine ssh 'mkdir -p ${dir} && printf "[[registry]]\\nlocation = \\"localhost:${FLOCI_PORT}\\"\\ninsecure = true\\n" > ${dir}/floci.conf'
  podman machine ssh 'printf "[[registry]]\\nlocation = \\"${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com\\"\\nblocked = true\\n" > ${dir}/floci-block-ecr.conf'
EOF
  exit 2
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
    # Task, Lambda, RDS and Redis containers join FLOCI_NETWORK; the RDS endpoints name this container, which is
    # how a task reaches the database through Floci's proxy. FLOCI_HOSTNAME does the same for the Redis endpoints
    # (ECR URIs keep the localhost form). The sysctl lets the ALB listeners bind 80 and 443 in a
    # rootless container.
    "$rt" run -d --name "$FLOCI_CONTAINER" --network "$FLOCI_NETWORK" \
      -p "127.0.0.1:${FLOCI_PORT}:4566" \
      -p "127.0.0.1:${ALB_PORT}:443" \
      -v "$(runtime_socket):/var/run/docker.sock" \
      --security-opt label=disable \
      --sysctl net.ipv4.ip_unprivileged_port_start=0 \
      -e FLOCI_DEFAULT_ACCOUNT_ID="$ACCOUNT_ID" \
      -e FLOCI_SERVICES_LAMBDA_DOCKER_NETWORK="$FLOCI_NETWORK" \
      -e FLOCI_SERVICES_ECS_DOCKER_NETWORK="$FLOCI_NETWORK" \
      -e FLOCI_SERVICES_RDS_ENDPOINT_HOST="$FLOCI_CONTAINER" \
      -e FLOCI_HOSTNAME="$FLOCI_CONTAINER" \
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
  "edge/logs.tf|Floci ${FLOCI_IMAGE##*:} 不支援 CloudWatch Logs delivery（PutDeliveryDestination）"
  "agent/logs.tf|Floci ${FLOCI_IMAGE##*:} 不支援 CloudWatch Logs delivery（PutDeliveryDestination）"
)

# Top-level blocks removed from the copy for the same reason, when the rest of the file is still needed.
# Format: <stack>/<file>|<block header line>|<reason>
SKIPPED_BLOCKS=(
  "loadbalancer/alb.tf|module \"alb_access_logs\" {|Floci ${FLOCI_IMAGE##*:} 不支援 CloudWatch Logs delivery（PutDeliverySource）"
)

# remove_block <file> <header line>: delete one top-level block, from its header to the first "}" at column 0.
remove_block() {
  local f="$1" header="$2"
  [ "$(grep -cxF "$header" "$f")" -eq 1 ] || die "${f#"${work_tf}/"} 找不到「${header}」，floci.sh 要跟著改"
  HEADER="$header" perl -0pi -e 's/^\Q$ENV{HEADER}\E\n.*?^\}\n//ms' "$f"
}

# tfvars values changed in the copy. Format: <stack>|<variable>|<value>|<reason>
TFVARS_OVERRIDES=(
  "operation|bastion_enabled|false|Floci ${FLOCI_IMAGE##*:} 的 DescribeInstanceTypes 查不到 t4g.nano；bastion 不在請求路徑上"
  "postdeploy|tracing_enabled|false|Floci ${FLOCI_IMAGE##*:} 不支援 CloudWatch Logs delivery（trace 送 X-Ray 走 PutDeliverySource）"
)

override_tfvars() {
  local entry stack var value reason f
  for entry in "${TFVARS_OVERRIDES[@]}"; do
    IFS='|' read -r stack var value reason <<<"$entry"
    f="${work_tf}/${stack}/envs/${ENV_NAME}.tfvars"
    [ "$(grep -cE "^${var} *=" "$f")" -eq 1 ] || die "${stack}/envs/${ENV_NAME}.tfvars 沒有 ${var}，floci.sh 要跟著改"
    VAR="$var" VALUE="$value" perl -pi -e 's/^\Q$ENV{VAR}\E *=.*$/$ENV{VAR} = $ENV{VALUE}/' "$f"
    echo "  ${stack}：${var} 改成 ${value}（${reason}）"
  done
}

# Lines removed from a module the copy downloaded (after init), where Floci rejects an argument the module always
# sends. Format: <stack>|<path under .terraform-<env>/modules>|<first line>|<line count>|<reason>
MODULE_PATCHES=(
  "agent|runtime/main.tf|  lifecycle_configuration = [{|4|Floci ${FLOCI_IMAGE##*:} 不保存 AgentCore runtime 的 lifecycleConfiguration，provider 報 inconsistent result"
)

patch_modules() {
  local entry stack path first count reason f
  for entry in "${MODULE_PATCHES[@]}"; do
    IFS='|' read -r stack path first count reason <<<"$entry"
    f="${work_tf}/${stack}/.terraform-${ENV_NAME}/modules/${path}"
    [ -f "$f" ] || die "找不到 ${stack} 下載的 module 檔案 ${path}，先跑 init"
    if grep -qxF "$first" "$f"; then
      FIRST="$first" REST="$((count - 1))" perl -0pi -e 's/^\Q$ENV{FIRST}\E\n(?:.*\n){$ENV{REST}}//m' "$f"
      echo "  ${stack} 的 module ${path}：拿掉「${first# }」起 ${count} 行（${reason}）"
    fi
  done
}

# Second-plan diffs that come from Floci's responses, checked against the API on Floci 2.4.0; any other diff fails.
# Format: <stack>|<resource address>|<reason>
KNOWN_DRIFT=(
  "database|module.db.aws_rds_cluster.this[0]|DescribeDBClusters 不回備份保留天數、備份與維護時段、log 匯出、security group，port 回 proxy 的 7001"
  "database|module.db.aws_rds_cluster_parameter_group.this[0]|cluster parameter group 不保存參數"
  "database|module.redis[\"rate-limit\"].aws_elasticache_replication_group.this|不保存 log_delivery_configuration；兩組 Redis 都要 6379，晚建的那組被分到別的 port，plan 要重建它"
  "database|module.redis[\"stream\"].aws_elasticache_replication_group.this|同上一筆（哪一組拿到 6379 每次不一定）"
  "database|module.ssm_publish.aws_ssm_parameter.string[\"rate_limit_redis_endpoint\"]|跟著被重建的 Redis 變動"
  "database|module.ssm_publish.aws_ssm_parameter.string[\"stream_redis_endpoint\"]|跟著被重建的 Redis 變動"
  "edge|module.cdn.aws_cloudfront_distribution.this|distribution 不保存 WebACLId"
  "operation|module.lambda[\"import-extract\"].aws_lambda_function.this|GetFunction 在沒設定時仍回空的 ImageConfig"
  "operation|module.lambda[\"import-load\"].aws_lambda_function.this|GetFunction 在沒設定時仍回空的 ImageConfig"
  "postdeploy|module.service_alarms[\"api\"].aws_cloudwatch_metric_alarm.this[\"latency_p95\"]|DescribeAlarms 不回 ExtendedStatistic"
)

order() {
  # The same line check-ssm-contract.sh parses.
  sed -n 's/^ORDER=(\(.*\))$/\1/p' "${template_tf}/stacks.sh"
}

# Floci's ECR returns <account>.dkr.ecr.<region>.localhost:<port>/<repo>. ecs-service, lambda-function and
# agentcore-runtime only accept AWS-shaped URIs, so the copy, and only the copy, publishes the URLs with the AWS host;
# Floci rewrites them back to its own registry when it pulls, and Podman blocks the real host (podman_registry_check).
patch_ecr_urls() {
  local f="${work_tf}/containerimage/ssm-outputs.tf"
  local from='key => repo.url })'
  local to="key => replace(repo.url, \".localhost:${FLOCI_PORT}/\", \".amazonaws.com/\") })"
  [ "$(grep -cF "$from" "$f")" -eq 1 ] || die "containerimage/ssm-outputs.tf 的 ecr_repository_urls 寫法變了，floci.sh 要跟著改"
  FROM="$from" TO="$to" perl -0pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/' "$f"
}

cmd_prepare() {
  floci_env
  log "複製 example2 到 ${WORK_DIR}"
  rm -rf "$work_tf"
  mkdir -p "$WORK_DIR"
  rsync -a --exclude '.terraform/' --exclude '.terraform-*/' "${template_tf}/" "${work_tf}/"
  local s
  for s in $(order); do
    cp "${here}/provider_override.tf.tmpl" "${work_tf}/${s}/floci_override.tf"
    write_backend "$s"
  done
  patch_ecr_urls
  override_tfvars
  local entry
  for entry in "${SKIPPED_FILES[@]}"; do
    rm "${work_tf}/${entry%%|*}"
    echo "  略過 ${entry%%|*}：${entry#*|}"
  done
  local file header
  for entry in "${SKIPPED_BLOCKS[@]}"; do
    IFS='|' read -r file header _ <<<"$entry"
    remove_block "${work_tf}/${file}" "$header"
    echo "  略過 ${file} 的 ${header% \{}：$(echo "$entry" | cut -d'|' -f3-)"
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
  patch_modules
}

# The origin verify value lives only in the work directory: loadbalancer requires it (TF_VAR_), trace sends it.
load_origin_verify() {
  local f="${WORK_DIR}/origin-verify"
  if [ ! -s "$f" ]; then
    (umask 077 && openssl rand -hex 24 | tr -d '\n' >"$f")
  fi
  TF_VAR_origin_verify_header_value="$(cat "$f")"
  export TF_VAR_origin_verify_header_value
}

# Images the copy needs, as <repository key>|<stub directory>|<tfvars file>|<tag variable>. The agent image is not
# built: Floci's AgentCore keeps runtimes as metadata and never starts their container.
IMAGES=(
  "api|app-stub|application|api_image_tag"
  "worker|app-stub|application|worker_image_tag"
  "import-extract|lambda-stub|operation|import_extract_image_tag"
  "import-load|lambda-stub|operation|import_load_image_tag"
)

push_stub_images() {
  local rt urls entry key dir stack var repo tag image
  rt="$(runtime)"
  urls="$(awsl ssm get-parameter --name "/${PROJECT}/${ENV_NAME}/containerimage/ecr_repository_urls" \
    --query Parameter.Value --output text)"
  for entry in "${IMAGES[@]}"; do
    IFS='|' read -r key dir stack var <<<"$entry"
    repo="$(echo "$urls" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())[sys.argv[1]])' "$key")"
    # Always push to Floci's own registry, never under the AWS name.
    repo="${repo/.amazonaws.com\//.localhost:${FLOCI_PORT}/}"
    tag="$(sed -n "s/^${var} *= *\"\(.*\)\"$/\1/p" "${work_tf}/${stack}/envs/${ENV_NAME}.tfvars")"
    [ -n "$tag" ] || tag="$(sed -n "/variable \"${var}\"/,/^}/s/^ *default *= *\"\(.*\)\"$/\1/p" \
      "${work_tf}/${stack}/variables.tf")"
    if [ -z "$repo" ] || [ -z "$tag" ]; then
      die "拿不到 ${key} 的 repository 或 ${var}"
    fi
    image="${repo}:${tag}"
    if "$rt" image inspect "${image/.localhost:${FLOCI_PORT}\//.amazonaws.com/}" >/dev/null 2>&1; then
      die "本機有用 AWS registry 名稱命名的 ${key} 映像；先 ${rt} rmi 它"
    fi
    if awsl ecr describe-images --repository-name "${repo##*/}" --image-ids "imageTag=${tag}" >/dev/null 2>&1; then
      echo "  ${key}:${tag} 已在 repository 裡（tag 不可覆寫），不再推送"
      continue
    fi
    log "建置並推送 ${key}:${tag}（${dir}）"
    "$rt" build -q --platform linux/arm64 -t "$image" "${here}/${dir}" >/dev/null
    if [ "$rt" = podman ]; then
      "$rt" push -q --tls-verify=false "$image"
    else
      "$rt" push -q "$image"
    fi
  done
}

# AWS-managed prefix lists do not exist in Floci, and a customer-managed list cannot take a com.amazonaws. name.
# network takes the CloudFront origin-facing list by ID (tfvars) and application looks it up by name, so a
# customer-managed list stands in for it: the copy's tfvars gets its ID and application's lookup its name. The CIDR is
# a placeholder: nothing in Floci filters traffic by security group.
CDN_PREFIX_LIST_NAME=floci-cloudfront-origin-facing
TEMPLATE_PREFIX_LIST_NAME=com.amazonaws.global.cloudfront.origin-facing
TEMPLATE_PREFIX_LIST_ID=pl-58a04531

seed_prefix_list() {
  local id f="${work_tf}/network/envs/${ENV_NAME}.tfvars"
  id="$(awsl ec2 describe-managed-prefix-lists --filters "Name=prefix-list-name,Values=${CDN_PREFIX_LIST_NAME}" \
    --query 'PrefixLists[0].PrefixListId' --output text)"
  if [ -z "$id" ] || [ "$id" = None ]; then
    id="$(awsl ec2 create-managed-prefix-list --prefix-list-name "$CDN_PREFIX_LIST_NAME" --address-family IPv4 \
      --max-entries 5 --entries Cidr=130.176.0.0/18 --query 'PrefixList.PrefixListId' --output text)"
    log "建立 prefix list ${CDN_PREFIX_LIST_NAME}（${id}），代替 AWS 內建的 ${TEMPLATE_PREFIX_LIST_ID}"
  fi
  ID="$id" OLD="$TEMPLATE_PREFIX_LIST_ID" perl -pi -e 's/\Q$ENV{OLD}\E/$ENV{ID}/g' "$f"
  f="${work_tf}/application/environment.tf"
  # A second apply finds the name already replaced.
  [ "$(grep -cF -e "name = \"${TEMPLATE_PREFIX_LIST_NAME}\"" -e "name = \"${CDN_PREFIX_LIST_NAME}\"" "$f")" -eq 1 ] ||
    die "application/environment.tf 查 prefix list 的寫法變了，floci.sh 要跟著改"
  NEW="$CDN_PREFIX_LIST_NAME" OLD="$TEMPLATE_PREFIX_LIST_NAME" perl -pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/g' "$f"
}

cmd_apply() {
  require_work
  floci_env
  load_origin_verify
  seed_prefix_list
  stacks containerimage apply --yes
  push_stub_images
  stacks all apply --yes
}

# only_known_drift <stack> <plan log>: true when every resource the plan changes is listed in KNOWN_DRIFT.
only_known_drift() {
  local stack="$1" planlog="$2" addr entry known
  while IFS= read -r addr; do
    known=0
    for entry in ${KNOWN_DRIFT[@]+"${KNOWN_DRIFT[@]}"}; do
      if [ "${entry%%|*}" = "$stack" ] && [ "$(echo "$entry" | cut -d'|' -f2)" = "$addr" ]; then
        known=1
        echo "    ${addr}：$(echo "$entry" | cut -d'|' -f3-)"
      fi
    done
    [ "$known" -eq 1 ] || return 1
  done < <(sed 's/\x1b\[[0-9;]*m//g' "$planlog" | sed -n 's/^  # \(.*\) will be .*$/\1/p; s/^  # \(.*\) must be .*$/\1/p')
}

cmd_status() {
  require_work
  floci_env
  local s rt
  log "各 stack 在 Floci 建的 AWS 資源（依類型計數）"
  for s in $(order); do
    echo "  [${s}]"
    tf_in "$s" state list 2>/dev/null | grep -v '^data\.' | grep -v '\.data\.' |
      sed -E 's/.*\.(aws[a-z]*_[a-z0-9_]+)\.[^.]+$/\1/' | sort | uniq -c | sed 's/^/    /' || true
  done

  rt="$(runtime)"
  log "Floci 起的 container（ECS task、Lambda、RDS、Redis、ECR registry）"
  "$rt" ps --filter label=floci=true --format '  {{.Names}}  |  {{.Image}}  |  {{.Status}}'

  log "ECS"
  local cluster svc
  for cluster in $(awsl ecs list-clusters --query 'clusterArns[]' --output text); do
    for svc in $(awsl ecs list-services --cluster "$cluster" --query 'serviceArns[]' --output text); do
      awsl ecs describe-services --cluster "$cluster" --services "$svc" \
        --query 'services[0].[serviceName,status,desiredCount,runningCount]' --output text | sed 's/^/  service: /'
    done
  done

  log "ALB target health"
  local tg
  for tg in $(awsl elbv2 describe-target-groups --query 'TargetGroups[].TargetGroupArn' --output text); do
    echo "  ${tg##*:targetgroup/}"
    awsl elbv2 describe-target-health --target-group-arn "$tg" \
      --query 'TargetHealthDescriptions[].[Target.Id,Target.Port,TargetHealth.State]' --output text | sed 's/^/    /'
  done

  log "RDS 與 Redis endpoint"
  awsl rds describe-db-clusters --query 'DBClusters[].[DBClusterIdentifier,Endpoint,Port,Status]' --output text |
    sed 's/^/  cluster: /'
  awsl rds describe-db-proxies --query 'DBProxies[].[DBProxyName,Endpoint,Status]' --output text | sed 's/^/  proxy: /'
  awsl elasticache describe-replication-groups \
    --query 'ReplicationGroups[].[ReplicationGroupId,Status,ConfigurationEndpoint.Address||NodeGroups[0].PrimaryEndpoint.Address]' \
    --output text | sed 's/^/  redis: /'
}

# The ALB serves HTTPS with a certificate Floci made up, hence -k; the Host header picks the api listener rule.
alb_get() {
  local path="$1"
  shift
  curl -sk --max-time 30 -H "Host: ${API_HOST}" "$@" "https://localhost:${ALB_PORT}${path}"
}

cmd_trace() {
  require_work
  floci_env
  load_origin_verify
  local failed=0 code body
  log "請求路徑：client → ALB（https://localhost:${ALB_PORT}，Host ${API_HOST}）→ ECS api → 各個依賴"

  code="$(alb_get /api/quota -o /dev/null -w '%{http_code}' || true)"
  echo "  沒帶 ${ORIGIN_HEADER}：ALB 回 ${code}（要 404，規則不符落到預設回應）"
  [ "$code" = 404 ] || failed=1

  code="$(alb_get /health -o /dev/null -w '%{http_code}' || true)"
  echo "  /health 不在 ALB 規則裡：回 ${code}（要 404）"

  body="$(alb_get /api/quota -H "${ORIGIN_HEADER}: ${TF_VAR_origin_verify_header_value}" || true)"
  echo "  帶 ${ORIGIN_HEADER} 打 /api/quota："
  local rc=0
  echo "$body" | python3 "${here}/trace_report.py" || rc=$?
  case "$rc" in
    0) ;;
    1) failed=1 ;;
    *)
      echo "    回應不是預期的 trace：$(echo "$body" | head -c 300)"
      failed=1
      ;;
  esac

  log "worker 從 stream Redis 收到的訊息（最近 3 筆 log）"
  local rt worker
  rt="$(runtime)"
  worker="$("$rt" ps --filter label=floci=true --format '{{.Names}} {{.Image}}' | awk '$2 ~ /-worker:/ {print $1; exit}')"
  if [ -n "$worker" ]; then
    "$rt" logs --tail 3 "$worker" 2>&1 | sed 's/^/  /'
  else
    echo "  找不到 worker 的 container"
  fi
  return "$failed"
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
  awsl ssm get-parameters-by-path --path "/${PROJECT}" --recursive --query 'length(Parameters)' --output text |
    sed 's/^/  樹 A：/'
  awsl ssm get-parameters-by-path --path "/${PROJECT}-shared/${ENV_NAME}/infra" --recursive \
    --query 'length(Parameters)' --output text | sed 's/^/  樹 B：/'

  cmd_trace || failed=1

  if [ "$failed" -eq 0 ]; then log "verify 全部通過"; else log "verify 有項目沒通過"; fi
  return "$failed"
}

# REFERENCE.md〈destroy 之前〉: the repositories have force_delete = false, so they are emptied first.
empty_repositories() {
  local addr repo ids d
  local -a digests image_ids
  for addr in $(tf_in containerimage state list 2>/dev/null | grep 'aws_ecr_repository.this$' || true); do
    repo="$(tf_in containerimage state show -no-color "$addr" | sed -n 's/^ *name *= *"\(.*\)"$/\1/p')"
    ids="$(awsl ecr list-images --repository-name "$repo" --query 'imageIds[].imageDigest' --output text)"
    if [ -z "$ids" ] || [ "$ids" = None ]; then
      continue
    fi
    log "清空 ECR repository ${repo}"
    image_ids=()
    read -ra digests <<<"$ids"
    for d in "${digests[@]}"; do image_ids+=("imageDigest=${d}"); done
    awsl ecr batch-delete-image --repository-name "$repo" --image-ids "${image_ids[@]}" >/dev/null
  done
}

cmd_destroy() {
  require_work
  floci_env
  load_origin_verify
  empty_repositories
  stacks all destroy --yes
}

# Floci keeps the ECR registry, task, Lambda, RDS and Redis containers as labelled siblings with data volumes, which
# outlive the emulator's in-memory state; leaving them makes the next run find things its state never created.
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
  run | up | prepare | init | apply | verify | status | trace | destroy | down) "cmd_${action}" ;;
  -h | --help | help) usage ;;
  *)
    usage
    exit 2
    ;;
esac
