#!/usr/bin/env bash
# Run example4 end to end against Floci, a local AWS emulator, without touching a real account.
# The template is never modified: it is copied outside the repo, each stack gets a provider override and a backend
# file that point at Floci, and the copy's own stacks.sh runs in ORDER. See README.md for what this proves and what not.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template_tf="$(cd "${here}/../terraform" && pwd)"

FLOCI_IMAGE="${FLOCI_IMAGE:-docker.io/floci/floci:2.4.0}"
FLOCI_CONTAINER="${FLOCI_CONTAINER:-floci-example4}"
FLOCI_NETWORK="${FLOCI_NETWORK:-floci-net}"
FLOCI_PORT="${FLOCI_PORT:-4566}"
# Outside the repo: validate.sh scans every .tf under templates/.
tmp_root="${TMPDIR:-/tmp}"
WORK_DIR="${FLOCI_WORK_DIR:-${tmp_root%/}/floci-example4}"
ENV_NAME=dev
REGION=ap-northeast-1
ACCOUNT_ID=111111111111
PROJECT=example
STATE_BUCKET=example-dev-tfstate-floci
# localhost, not 127.0.0.1: S3 Control prefixes the account ID to the host, and <account>.localhost still resolves
# to loopback while <account>.127.0.0.1 does not.
endpoint="http://localhost:${FLOCI_PORT}"
work_tf="${WORK_DIR}/terraform"

usage() {
  cat >&2 <<'USAGE'
用法：floci.sh <run|up|prepare|init|apply|verify|status|trace|destroy|down>

  run      up → prepare → init → apply → verify → destroy，一次跑完（預設）
  up       啟動 Floci container（已在跑就沿用）
  prepare  把 example4 複製到 FLOCI_WORK_DIR，換上指向 Floci 的 provider 與 backend，建 state bucket
  init     複本的 stacks.sh dev all init
  apply    依 ORDER apply 全部
  verify   每個 stack 再 plan 一次要沒有變更，列出 SSM 參數，再跑 trace
  status   列出各 stack 建了哪些 AWS 資源、Floci 起了哪些 container、資料管線各元件的狀態
  trace    從 Kinesis 送幾筆資料進去，看它們流到哪裡
  destroy  依 ORDER 反向 destroy
  down     移除 Floci 和它啟動的 container、volume
USAGE
}

die() {
  echo "錯誤：$*" >&2
  exit 2
}

log() { echo "== $*"; }

# Docker if present, otherwise Podman. Floci starts its OpenSearch container through the runtime's socket.
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
  # Read by the copy's search-config (floci_vars.tf); a placeholder until search created the domain.
  TF_VAR_floci_opensearch_url="$(opensearch_url)"
  export TF_VAR_floci_opensearch_url="${TF_VAR_floci_opensearch_url:-http://localhost:1}"
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

cmd_up() {
  local rt
  rt="$(runtime)"
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
      -e FLOCI_DEFAULT_ACCOUNT_ID="$ACCOUNT_ID" \
      -e FLOCI_SERVICES_FIREHOSE_FLUSH_RECORD_COUNT="$TRACE_RECORDS" \
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

# Stacks removed from the copy's ORDER because Floci has no API for what they create. Nothing reads their outputs.
# Format: <stack>|<reason>
SKIPPED_STACKS=(
  "bi|Floci ${FLOCI_IMAGE##*:} 沒有 QuickSight"
)

skip_stacks() {
  local f="${work_tf}/stacks.sh" entry stack
  for entry in "${SKIPPED_STACKS[@]}"; do
    stack="${entry%%|*}"
    grep -q "^ORDER=(.* ${stack}[ )]" "$f" || die "stacks.sh 的 ORDER 沒有 ${stack}，floci.sh 要跟著改"
    STACK="$stack" perl -pi -e 's/^(ORDER=\(.*) \Q$ENV{STACK}\E([ )])/$1$2/' "$f"
    echo "  略過 ${stack} stack：${entry#*|}"
  done
}

# Top-level blocks removed from the copy, when the rest of the file is still needed.
# Format: <stack>/<file>|<block header line>|<reason>
SKIPPED_BLOCKS=()

# remove_block <file> <header line>: delete one top-level block, from its header to the first "}" at column 0.
remove_block() {
  local f="$1" header="$2"
  [ "$(grep -cxF "$header" "$f")" -eq 1 ] || die "${f#"${work_tf}/"} 找不到「${header}」，floci.sh 要跟著改"
  HEADER="$header" perl -0pi -e 's/^\Q$ENV{HEADER}\E\n.*?^\}\n//ms' "$f"
}

# Single lines replaced in the copy. Each line must appear exactly once, so a template change stops prepare.
# Format: <stack>/<file>|<line>|<replacement>|<reason>
LINE_PATCHES=(
  "search-config/envs/dev.tfvars|  warm_days       = 3|  warm_days       = null|Floci 的 OpenSearch 是開源版，沒有 AWS 的 UltraWarm（ISM 的 warm_migration）"
  "search-config/envs/dev.tfvars|  cold_days       = 7|  cold_days       = null|Floci 的 OpenSearch 是開源版，沒有 AWS 的 cold storage（ISM 的 cold_migration、cold_delete）"
  "search-config/config.tf|  writer_roles    = local.writer_roles|  writer_roles    = {}|Floci 的 OpenSearch 關掉 security plugin，FGAC 的 role 與 role mapping 建不起來"
  "search-config/ssm-outputs.tf|    firehose_writer_role = one(module.config.writer_role_names)|    firehose_writer_role = \"firehose_writer\"|上一行不建 writer role，改發布範本原本會發布的名稱"
  "analytics/workgroup.tf|  named_queries                  = local.named_queries|  named_queries                  = {}|Floci ${FLOCI_IMAGE##*:} 不支援 Athena CreateNamedQuery；trace 直接跑同一句 SQL"
  "search-config/providers.tf|  opensearch_url    = \"https://\${module.in.strings[\"opensearch_endpoint\"]}\"|  opensearch_url    = var.floci_opensearch_url|Floci 發布的 endpoint 是 container 內部的 http 位址，本機要連 container 對外的 port（floci_vars.tf）"
)

# replace_line <stack>/<file> <line> <replacement>: the line must appear exactly once; \n in the replacement adds lines.
replace_line() {
  local file="$1" line="$2" repl="$3" f="${work_tf}/$1"
  [ "$(grep -cxF "$line" "$f")" -eq 1 ] || die "${file} 找不到「${line# *}」，floci.sh 要跟著改"
  LINE="$line" REPL="$repl" perl -pi -e 's/^\Q$ENV{LINE}\E$/$ENV{REPL} =~ s{\\n}{\n}gr/e' "$f"
}

patch_lines() {
  local entry file line repl reason
  for entry in "${LINE_PATCHES[@]}"; do
    IFS='|' read -r file line repl reason <<<"$entry"
    replace_line "$file" "$line" "$repl"
    echo "  ${file}：${line#"${line%%[! ]*}"} 改成 ${repl#"${repl%%[! ]*}"}（${reason}）"
  done
  cat >"${work_tf}/search-config/floci_vars.tf" <<'EOF'
# Generated by floci.sh: the URL of the OpenSearch container Floci started, as the host reaches it.
variable "floci_opensearch_url" {
  type = string
}
EOF
}

# Lines removed from a module the copy downloaded (after init), where Floci answers differently from AWS.
# Format: <stack>|<path under .terraform-<env>/modules>|<first line>|<line count>|<reason>
MODULE_PATCHES=(
  "search|domain/main.tf|  vpc_options {|4|Floci ${FLOCI_IMAGE##*:} 的 VPC domain 回 Endpoint 而不是 Endpoints[\"vpc\"]，provider 讀回時報錯；拿掉後當成公開 domain"
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

# The host port Floci published for the domain's OpenSearch container, as a URL for search-config (empty before the
# search stack created the domain).
OPENSEARCH_CONTAINER="floci-aws-opensearch-${ACCOUNT_ID}-${REGION}-${PROJECT}-${ENV_NAME}-search"

opensearch_url() {
  local port
  port="$("$(runtime)" port "$OPENSEARCH_CONTAINER" 9200/tcp 2>/dev/null | head -1 | sed 's/.*://')"
  [ -z "$port" ] || echo "http://localhost:${port}"
}

# Second-plan diffs that come from Floci's responses, checked against the API on Floci 2.4.0; any other diff fails.
# Format: <stack>|<resource address>|<reason>
KNOWN_DRIFT=(
  "search|module.domain.aws_opensearch_domain.this|DescribeDomain 不回 dedicated master、UltraWarm、cold storage、zone awareness 與 log publishing 設定"
  "analytics|module.workgroup.aws_athena_workgroup.this|GetWorkGroup 不回查詢結果的 SSE_KMS 加密設定"
  "pipeline|module.firehose_opensearch.aws_kinesis_firehose_delivery_stream.this|不保存 OpenSearch 目的地，讀回來是 extended_s3，plan 要重建"
  "pipeline|module.ssm_publish.aws_ssm_parameter.string[\"firehose_opensearch_arn\"]|跟著被重建的 Firehose 變動"
)

# Resources Floci can create but not delete: destroy drops them from state instead, and down discards Floci's copy.
# Format: <stack>|<resource address>|<reason>
UNDELETABLE=(
  "search|module.domain.aws_cloudwatch_log_resource_policy.this|Floci ${FLOCI_IMAGE##*:} 不支援 CloudWatch Logs DeleteResourcePolicy"
)

forget_undeletable() {
  local entry stack addr
  for entry in "${UNDELETABLE[@]}"; do
    stack="${entry%%|*}"
    addr="$(echo "$entry" | cut -d'|' -f2)"
    if tf_in "$stack" state list "$addr" 2>/dev/null | grep -qxF "$addr"; then
      echo "  ${stack}：${addr} 從 state 移除，不 destroy（$(echo "$entry" | cut -d'|' -f3-)）"
      tf_in "$stack" state rm "$addr" >/dev/null
    fi
  done
}

# The copy's ORDER, which is the template's minus SKIPPED_STACKS once prepare ran.
order() {
  local f="${work_tf}/stacks.sh"
  [ -f "$f" ] || f="${template_tf}/stacks.sh"
  sed -n 's/^ORDER=(\(.*\))$/\1/p' "$f"
}

cmd_prepare() {
  floci_env
  log "複製 example4 到 ${WORK_DIR}"
  rm -rf "$work_tf"
  mkdir -p "$WORK_DIR"
  rsync -a --exclude '.terraform/' --exclude '.terraform-*/' "${template_tf}/" "${work_tf}/"
  skip_stacks
  local s
  for s in $(order); do
    cp "${here}/provider_override.tf.tmpl" "${work_tf}/${s}/floci_override.tf"
    write_backend "$s"
  done
  patch_lines
  local entry file header
  for entry in ${SKIPPED_BLOCKS[@]+"${SKIPPED_BLOCKS[@]}"}; do
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

# REFERENCE.md〈前置作業〉item 2: search reads the master secret at plan time, so it gets a value after foundation.
# The same pipe as REFERENCE.md: the password never appears in an argument or a shell variable.
MASTER_SECRET="${PROJECT}-${ENV_NAME}/opensearch-master"

seed_master_secret() {
  # Floci's CreateSecret adds an AWSCURRENT version without a value, so the check is on SecretString, not the version.
  # The value itself is not kept: only whether one exists.
  if awsl secretsmanager get-secret-value --secret-id "$MASTER_SECRET" --query SecretString --output text \
    2>/dev/null | grep -qv '^None$'; then
    return 0
  fi
  log "寫入 ${MASTER_SECRET} 的值（REFERENCE.md〈前置作業〉第 2 項）"
  awsl secretsmanager get-random-password --password-length 32 --require-each-included-type \
    --query RandomPassword --output text |
    python3 -c 'import json,sys; print(json.dumps({"username": "master", "password": sys.stdin.read().strip()}))' |
    awsl secretsmanager put-secret-value --secret-id "$MASTER_SECRET" --secret-string file:///dev/stdin >/dev/null
}

# search-config talks to the OpenSearch container directly, and once found it not answering right after search
# finished (cause not seen). Wait for it, and show the container state and log when it never answers.
wait_opensearch() {
  local _
  for _ in $(seq 1 120); do
    if [ -n "$TF_VAR_floci_opensearch_url" ] && curl -sf --max-time 2 "$TF_VAR_floci_opensearch_url" >/dev/null; then
      return 0
    fi
    sleep 1
  done
  "$(runtime)" ps -a --filter "name=${OPENSEARCH_CONTAINER}" --format '  {{.Names}}  |  {{.Status}}' >&2
  "$(runtime)" logs --tail 20 "$OPENSEARCH_CONTAINER" >&2 2>&1 || true
  die "OpenSearch 120 秒內沒有回應：${TF_VAR_floci_opensearch_url}"
}

cmd_apply() {
  require_work
  floci_env
  local s
  # One stack at a time: search-config needs the OpenSearch port, which exists only once search created the domain.
  for s in $(order); do
    floci_env
    [ "$s" != search-config ] || wait_opensearch
    stacks "$s" apply --yes
    [ "$s" != foundation ] || seed_master_secret
  done
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
  local s
  log "各 stack 在 Floci 建的 AWS 資源（依類型計數）"
  for s in $(order); do
    echo "  [${s}]"
    tf_in "$s" state list 2>/dev/null | grep -v '^data\.' | grep -v '\.data\.' |
      sed -E 's/.*\.(aws[a-z]*_[a-z0-9_]+|opensearch_[a-z0-9_]+)\.[^.]+$/\1/' | sort | uniq -c | sed 's/^/    /' || true
  done

  log "Floci 起的 container（OpenSearch、Redshift、Athena 用的 DuckDB）"
  "$(runtime)" ps --filter label=floci=true --format '  {{.Names}}  |  {{.Image}}  |  {{.Status}}'

  local prefix="${PROJECT}-${ENV_NAME}" f
  log "資料管線"
  awsl kinesis describe-stream-summary --stream-name "${prefix}-events" \
    --query 'StreamDescriptionSummary.[StreamName,StreamStatus,OpenShardCount]' --output text | sed 's/^/  kinesis: /'
  # shellcheck disable=SC2016 # backticks are JMESPath literals
  for f in $(awsl firehose list-delivery-streams --query 'DeliveryStreamNames[]' --output text); do
    awsl firehose describe-delivery-stream --delivery-stream-name "$f" --query \
      'DeliveryStreamDescription.[DeliveryStreamName,DeliveryStreamStatus,Destinations[0].ExtendedS3DestinationDescription.BucketARN||`(沒有 S3 目的地)`]' \
      --output text | sed 's/^/  firehose: /'
  done
  awsl opensearch describe-domain --domain-name "${prefix}-search" \
    --query 'DomainStatus.[DomainName,EngineVersion,Endpoint]' --output text | sed "s|\$|  本機：$(opensearch_url)|; s/^/  opensearch: /"
  # shellcheck disable=SC2016 # backticks are JMESPath literals
  awsl glue get-workflow --name "${prefix}-raw-to-curated" --query 'Workflow.[Name,LastRun.Status||`(還沒跑過)`]' \
    --output text | sed 's/^/  glue workflow: /'
  awsl glue list-jobs --query 'JobNames[]' --output text | sed 's/^/  glue job: /'
  awsl athena get-work-group --work-group "${prefix}-analytics" \
    --query 'WorkGroup.[Name,State,Configuration.ResultConfiguration.OutputLocation]' --output text | sed 's/^/  athena: /'
  awsl redshift-serverless list-workgroups \
    --query 'workgroups[].[workgroupName,status,endpoint.address,endpoint.port]' --output text | sed 's/^/  redshift: /'
  awsl dynamodb list-tables --query 'TableNames[]' --output text | sed 's/^/  dynamodb: /'
}

ssm() { awsl ssm get-parameter --name "/${PROJECT}/${ENV_NAME}/$1" --query Parameter.Value --output text; }

# hop <OK|KN|NG> <name> <detail>: one line of the trace; NG fails it. KN is a Floci gap listed in README.md.
hop() {
  printf '  %s  %s：%s\n' "$1" "$2" "$3"
  [ "$1" != NG ] || trace_failed=1
}

# new_keys <bucket> <prefix> <before file>: object keys under the prefix that were not in the snapshot.
new_keys() {
  awsl s3api list-objects-v2 --bucket "$1" --prefix "$2" --query 'Contents[].Key' --output text 2>/dev/null |
    tr '\t' '\n' | grep -v '^None$' | grep -vxF -f "$3" || true
}

# count_run <bucket> <keys...>: how many of the trace's records the (gzip) objects hold.
count_run() {
  local bucket="$1" key n=0 c
  shift
  for key in "$@"; do
    # to-raw writes gzip; to-search, with no S3 destination of its own, writes plain JSON.
    c="$(awsl s3 cp "s3://${bucket}/${key}" - | python3 -c 'import gzip,sys
b = sys.stdin.buffer.read()
sys.stdout.write((gzip.decompress(b) if b[:2] == b"\x1f\x8b" else b).decode())' |
      grep -o "\"run\": *\"${trace_run}\"" | wc -l)"
    n=$((n + c))
  done
  echo "$n"
}

# athena <workgroup> <sql>: run a query and print the first data row's first value, or the failure reason.
athena() {
  local id state _
  id="$(awsl athena start-query-execution --work-group "$1" --query-string "$2" --query QueryExecutionId --output text)"
  for _ in $(seq 1 30); do
    state="$(awsl athena get-query-execution --query-execution-id "$id" --query QueryExecution.Status.State --output text)"
    case "$state" in QUEUED | RUNNING) sleep 1 ;; *) break ;; esac
  done
  if [ "$state" = SUCCEEDED ]; then
    awsl athena get-query-results --query-execution-id "$id" --query 'ResultSet.Rows[1].Data[0].VarCharValue' --output text
  else
    echo "${state}: $(awsl athena get-query-execution --query-execution-id "$id" \
      --query QueryExecution.Status.StateChangeReason --output text | head -c 200)"
    return 1
  fi
}

# Records per trace; cmd_up passes it to Floci as the Firehose flush count, so both streams flush as soon as the
# trace's records arrive instead of after the template's buffering interval (900 s for to-raw).
TRACE_RECORDS=5
# Stand-in for the table the raw crawler would create: Floci's crawler finishes without reading S3.
TRACE_TABLE=floci_trace

cmd_trace() {
  require_work
  floci_env
  trace_failed=0
  local prefix="${PROJECT}-${ENV_NAME}" stream raw_bucket raw_db workgroup url index started before keys n verdict
  trace_run="trace-$(date -u +%Y%m%dT%H%M%S)"
  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  stream="$(ssm storage/stream_arn)"
  raw_bucket="$(ssm storage/raw_bucket_name)"
  raw_db="$(ssm storage/raw_database_name)"
  workgroup="$(ssm analytics/athena_workgroup_name)"
  log "資料流：Kinesis → Firehose → S3 raw → EventBridge → Glue → Athena；另外看 OpenSearch、Redshift、DynamoDB（run=${trace_run}）"

  before="${WORK_DIR}/trace-before"
  { new_keys "$raw_bucket" raw/ /dev/null; new_keys floci-firehose-results "" /dev/null; } >"$before"

  # 1. The producer's side: records into the stream both Firehose streams read.
  python3 - "$trace_run" "$TRACE_RECORDS" >"${WORK_DIR}/trace-records.json" <<'EOF'
import base64, datetime, json, sys
run, n = sys.argv[1], int(sys.argv[2])
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
print(json.dumps([{"PartitionKey": f"{run}-{i}", "Data": base64.b64encode(json.dumps(
    {"event_id": f"{run}-{i}", "run": run, "@timestamp": now, "payload": f"event {i}"}).encode() + b"\n").decode()}
    for i in range(n)]))
EOF
  n="$(awsl kinesis put-records --stream-name "${stream##*/}" --records "file://${WORK_DIR}/trace-records.json" \
    --query FailedRecordCount --output text)"
  if [ "$n" = 0 ]; then
    hop OK "Kinesis ${stream##*/}" "PutRecords ${TRACE_RECORDS} 筆"
  else
    hop NG "Kinesis ${stream##*/}" "${n} 筆失敗"
  fi

  # 2. Firehose to-raw reads the stream and writes gzip JSON under raw/ (polled every second, flushed at the count).
  keys=""
  for _ in $(seq 1 60); do
    keys="$(new_keys "$raw_bucket" raw/ "$before")"
    [ -z "$keys" ] || break
    sleep 1
  done
  if [ -n "$keys" ]; then
    # shellcheck disable=SC2086 # one key per word
    n="$(count_run "$raw_bucket" $keys)"
    verdict=NG
    if [ "$n" -eq "$TRACE_RECORDS" ]; then verdict=OK; fi
    hop "$verdict" "Firehose ${prefix}-to-raw → S3" "s3://${raw_bucket}/$(echo "$keys" | head -1)（gzip，${n} 筆）"
  else
    hop NG "Firehose ${prefix}-to-raw → S3" "60 秒內 raw/ 沒有新物件（Floci 要用 floci.sh up 啟動才會照筆數 flush）"
  fi

  # 3. Firehose to-search: Floci delivers only to S3, so the records land in its default bucket.
  keys="$(new_keys floci-firehose-results "" "$before" | grep "${prefix}-to-search" || true)"
  local landed="沒有送出"
  # shellcheck disable=SC2086 # one key per word
  if [ -n "$keys" ]; then landed="$(count_run floci-firehose-results $keys) 筆落在 s3://floci-firehose-results"; fi
  hop KN "Firehose ${prefix}-to-search → OpenSearch" "Floci 不支援 OpenSearch 目的地，${landed}"

  # 4. OpenSearch: the same records, written directly as Firehose would, against what search-config set up.
  url="$(opensearch_url)"
  index="${prefix}-events"
  python3 -c 'import base64,json,sys
for r in json.load(open(sys.argv[1])):
    print(json.dumps({"index": {"_index": sys.argv[2]}})); print(base64.b64decode(r["Data"]).decode().strip())' \
    "${WORK_DIR}/trace-records.json" "$index" >"${WORK_DIR}/trace-bulk.ndjson"
  if [ -n "$url" ] && curl -sf -H 'Content-Type: application/x-ndjson' --data-binary "@${WORK_DIR}/trace-bulk.ndjson" \
    "${url}/_bulk?refresh=true" >/dev/null; then
    local summary
    summary="$(python3 - "$url" "$index" "$trace_run" <<'EOF'
import json, sys, time, urllib.parse, urllib.request
url, index, run = sys.argv[1:]
get = lambda p: json.load(urllib.request.urlopen(url + p))
# run is a text field (dynamic mapping); its keyword subfield matches this run only.
count = get(f"/{index}/_count?q=" + urllib.parse.quote(f'run.keyword:"{run}"'))["count"]
ts = get(f"/{index}/_mapping")[index]["mappings"]["properties"].get("@timestamp", {}).get("type")
# ISM attaches the policy shortly after the index is created, not at once.
for _ in range(15):
    explain = get(f"/_plugins/_ism/explain/{index}")[index]
    policy = explain.get("index.plugins.index_state_management.policy_id") or explain.get("policy_id")
    if policy:
        break
    time.sleep(1)
print(f"{count} {ts} {policy}")
EOF
)"
    read -r n ts policy <<<"$summary"
    verdict=NG
    if [ "$n" = "$TRACE_RECORDS" ] && [ "$ts" = date ] && [ "$policy" != None ]; then verdict=OK; fi
    hop "$verdict" "OpenSearch ${index}（代替 Firehose 直接寫入）" "${n} 筆；@timestamp 是 ${ts}（index template）；ISM policy ${policy}"
  else
    hop NG "OpenSearch ${index}" "寫入失敗（${url:-找不到 OpenSearch container}）"
  fi

  # 5. S3 Object Created → EventBridge rule → Glue workflow.
  # The event follows the Firehose write by a moment, so both signals are polled for a while.
  local wf runs matched=0
  wf="$(ssm pipeline/glue_workflow_name)"
  for _ in $(seq 1 15); do
    runs="$(awsl glue get-workflow-runs --name "$wf" --query 'length(Runs)' --output text 2>/dev/null || echo 0)"
    if [ "${runs:-0}" != 0 ] && [ "$runs" != None ]; then break; fi
    if "$(runtime)" logs --since "$started" "$FLOCI_CONTAINER" 2>&1 |
      grep -q "unsupported target ARN type: .*workflow/${wf}"; then
      matched=1
      break
    fi
    sleep 1
  done
  if [ "${runs:-0}" != 0 ] && [ "$runs" != None ]; then
    hop OK "S3 → EventBridge → Glue workflow ${wf}" "${runs} 次 workflow run"
  elif [ "$matched" -eq 1 ]; then
    hop KN "S3 → EventBridge → Glue workflow ${wf}" "rule 比對到 raw/ 的新物件，但 Floci 不支援 Glue workflow 當 target"
  else
    hop NG "S3 → EventBridge → Glue workflow ${wf}" "rule 沒有比對到 raw/ 的新物件"
  fi

  # 6. The Glue job the workflow would start, started by hand.
  local job run_id state
  job="$(awsl glue list-jobs --query 'JobNames[0]' --output text)"
  run_id="$(awsl glue start-job-run --job-name "$job" --query JobRunId --output text)"
  state="$(awsl glue get-job-run --job-name "$job" --run-id "$run_id" --query JobRun.JobRunState --output text)"
  verdict=KN
  if [ "$state" = FAILED ] || [ "$state" = ERROR ]; then verdict=NG; fi
  hop "$verdict" "Glue job ${job}" \
    "手動啟動，狀態 ${state}；Floci 只模擬 job run，不執行 script"

  # 7. Athena through the workgroup and the Glue catalog, over what Firehose wrote to raw/.
  if ! awsl glue get-table --database-name "$raw_db" --name "$TRACE_TABLE" >/dev/null 2>&1; then
    awsl glue create-table --database-name "$raw_db" --table-input "$(printf '%s' \
      '{"Name":"'"$TRACE_TABLE"'","TableType":"EXTERNAL_TABLE","Parameters":{"classification":"json"},' \
      '"StorageDescriptor":{"Location":"s3://'"$raw_bucket"'/raw/","Columns":[{"Name":"event_id","Type":"string"},' \
      '{"Name":"run","Type":"string"},{"Name":"payload","Type":"string"}],' \
      '"InputFormat":"org.apache.hadoop.mapred.TextInputFormat",' \
      '"OutputFormat":"org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",' \
      '"SerdeInfo":{"SerializationLibrary":"org.openx.data.jsonserde.JsonSerDe"}}}')"
  fi
  local answer
  if answer="$(athena "$workgroup" "SELECT count(*) FROM ${raw_db}.${TRACE_TABLE} WHERE run = '${trace_run}'")"; then
    verdict=NG
    if [ "$answer" = "$TRACE_RECORDS" ]; then verdict=OK; fi
    hop "$verdict" "Athena workgroup ${workgroup}" \
      "${raw_db}.${TRACE_TABLE} 查到 ${answer} 筆（table 由 trace 代替 crawler 建立）"
  else
    hop NG "Athena workgroup ${workgroup}" "$answer"
  fi

  # 8. Redshift through the Data API, as a client of the warehouse workgroup would query it.
  local wg db id
  wg="${prefix}-warehouse"
  db="$(ssm warehouse/redshift_database)"
  id="$(awsl redshift-data execute-statement --workgroup-name "$wg" --database "$db" --sql 'select version()' \
    --query Id --output text)"
  for _ in $(seq 1 30); do
    state="$(awsl redshift-data describe-statement --id "$id" --query Status --output text)"
    case "$state" in SUBMITTED | PICKED | STARTED) sleep 1 ;; *) break ;; esac
  done
  if [ "$state" = FINISHED ]; then
    hop OK "Redshift Serverless ${wg}" "Data API：$(awsl redshift-data get-statement-result --id "$id" \
      --query 'Records[0][0].stringValue' --output text | cut -d' ' -f1-2)（Floci 用 Postgres 代替）"
  else
    hop NG "Redshift Serverless ${wg}" "Data API ${state}：$(awsl redshift-data describe-statement --id "$id" \
      --query Error --output text | head -c 200)"
  fi

  # 9. The ingest bookkeeping table.
  local table key
  table="$(ssm storage/table_ingest_state_arn)"
  key='{"source_id":{"S":"'"$trace_run"'"},"ingested_at":{"S":"'"$started"'"}}'
  awsl dynamodb put-item --table-name "${table##*/}" \
    --item "${key%\}},\"expires_at\":{\"N\":\"$(($(date +%s) + 86400))\"}}" >/dev/null
  if [ "$(awsl dynamodb get-item --table-name "${table##*/}" --key "$key" --query 'Item.source_id.S' --output text)" = "$trace_run" ]; then
    hop OK "DynamoDB ${table##*/}" "PutItem、GetItem source_id=${trace_run}"
  else
    hop NG "DynamoDB ${table##*/}" "讀不回剛寫的項目"
  fi

  return "$trace_failed"
}

cmd_verify() {
  require_work
  floci_env
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

  cmd_trace || failed=1

  if [ "$failed" -eq 0 ]; then log "verify 全部通過"; else log "verify 有項目沒通過"; fi
  return "$failed"
}

# REFERENCE.md〈destroy 前要做的事〉: the buckets have force_destroy = false, so every version and delete marker goes
# first. The trace's Glue table is removed too: the template's raw database never declared it.
empty_buckets() {
  local bucket
  awsl glue delete-table --database-name "${PROJECT//-/_}_${ENV_NAME}_raw" --name "$TRACE_TABLE" >/dev/null 2>&1 || true
  for bucket in $(awsl s3api list-buckets --query "Buckets[?starts_with(Name, '${PROJECT}-${ENV_NAME}-')].Name" \
    --output text); do
    [ "$bucket" != "$STATE_BUCKET" ] || continue
    awsl s3api list-object-versions --bucket "$bucket" --output json |
      python3 -c 'import json,sys
d = json.load(sys.stdin)
for v in d.get("Versions", []) + d.get("DeleteMarkers", []):
    print(json.dumps({"Objects": [{"Key": v["Key"], "VersionId": v["VersionId"]}], "Quiet": True}))' |
      while IFS= read -r one; do
        awsl s3api delete-objects --bucket "$bucket" --delete "$one" >/dev/null
      done
    echo "  清空 ${bucket}"
  done
}

# REFERENCE.md〈destroy〉, done in the copy only: the DynamoDB table loses deletion protection through an apply, and
# the warehouse guard's prevent_destroy is lifted, so one destroy over every stack goes through.
lift_protections() {
  local pitr='  point_in_time_recovery_days = each.value.point_in_time_recovery_days'
  if ! grep -q 'deletion_protection *= false' "${work_tf}/storage/tables.tf"; then
    replace_line storage/tables.tf "$pitr" "${pitr}\n  deletion_protection         = false"
  fi
  stacks storage apply --yes
  if grep -qxF '    prevent_destroy = true' "${work_tf}/warehouse/guard.tf"; then
    replace_line warehouse/guard.tf '    prevent_destroy = true' '    prevent_destroy = false'
  fi
}

cmd_destroy() {
  require_work
  floci_env
  log "destroy 前的準備（REFERENCE.md〈destroy 前要做的事〉）"
  empty_buckets
  lift_protections
  forget_undeletable
  stacks all destroy --yes
}

# Floci keeps the containers it starts as labelled siblings with data volumes, which outlive the emulator's in-memory
# state; leaving them makes the next run find things its state never created.
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
