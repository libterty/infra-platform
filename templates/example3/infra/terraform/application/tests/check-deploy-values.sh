#!/usr/bin/env bash
# Offline check of the deploy contract consumer (design v4 §8.1): deploy/values-from-ssm.sh reads the eks-cluster and
# application keys and the chart in deploy/charts/app renders them. A fake `aws` serves fixed SSM values, so nothing
# reaches AWS or a cluster. Checks:
#   1. every key the script reads is published by eks-cluster, application or loadbalancer (their ssm-outputs.tf)
#   2. the api and worker values render, pass helm lint, and the manifests carry the contract values
#   3. the canary values (--canary) bind the api to the canary target group and reuse the ServiceAccount
#   4. the script refuses an unknown contract_version, a missing key and a canary that is not enabled
# Needs helm and jq; without helm it prints a skip line like scripts/validate.sh does.
set -euo pipefail

stack_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
terraform_dir="$(dirname "$stack_dir")"
deploy_dir="$(cd "${terraform_dir}/../../deploy" && pwd)"
script="${deploy_dir}/values-from-ssm.sh"
chart="${deploy_dir}/charts/app"

command -v jq >/dev/null || { echo "FAIL check-deploy-values: jq not found" >&2; exit 1; }
if ! command -v helm >/dev/null; then
  echo "略過 check-deploy-values：未安裝 helm" >&2
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
errors=0
fail() {
  echo "FAIL check-deploy-values: $*" >&2
  errors=$((errors + 1))
}

# ---- 1. keys read by the script are published ----

published_keys() {
  # Keys at depth 1 of the map local $2 (default published_strings, the format check-ssm-contract.sh relies on).
  awk -v map="${2:-published_strings}" '
    /^[[:space:]]*#/ { next }
    $0 ~ "^[[:space:]]*" map "[[:space:]]*=.*[{][[:space:]]*$" { in_map = 1; depth = 1; next }
    in_map {
      if (depth == 1 && match($0, /^[[:space:]]*[a-z][a-z0-9_]*[[:space:]]*=/)) {
        k = substr($0, RSTART, RLENGTH); gsub(/[[:space:]=]/, "", k); print k
      }
      t = $0; depth += gsub(/\{/, "", t); t = $0; depth -= gsub(/\}/, "", t)
      if (depth <= 0) in_map = 0
    }
  ' "$1"
}

# stack:map of the producer, then the array in the script that lists the keys read from it.
for entry in eks-cluster:published_strings:EKS_CLUSTER_KEYS application:published_strings:APPLICATION_KEYS loadbalancer:canary_strings:CANARY_KEYS; do
  IFS=: read -r stack map var <<<"$entry"
  published="$(published_keys "${terraform_dir}/${stack}/ssm-outputs.tf" "$map")"
  keys="$(sed -n "s/^${var}=(\(.*\))$/\1/p" "$script")"
  [ -n "$keys" ] || fail "values-from-ssm.sh has no single-line ${var}=(...)"
  for k in $keys; do
    grep -qx "$k" <<<"$published" || fail "values-from-ssm.sh reads ${stack}/${k}, which ${map} of ${stack}/ssm-outputs.tf does not publish"
  done
done

# ---- fake aws ----

mkdir -p "${work}/bin"
cat >"${work}/bin/aws" <<'FAKE'
#!/usr/bin/env bash
# Answers `aws ssm get-parameters-by-path --path <p> ...` from $FAKE_SSM_DIR/<p with / as _>.json.
path=""
while [ "$#" -gt 0 ]; do
  [ "$1" = "--path" ] && path="$2"
  shift
done
f="${FAKE_SSM_DIR}/$(printf '%s' "$path" | tr '/' '_').json"
[ -f "$f" ] || { echo "fake aws: no fixture for ${path}" >&2; exit 254; }
cat "$f"
FAKE
chmod +x "${work}/bin/aws"
export PATH="${work}/bin:${PATH}"
export FAKE_SSM_DIR="${work}/ssm"
mkdir -p "$FAKE_SSM_DIR"

# $1 = path, then key=value pairs.
fixture() {
  local path="$1"
  shift
  printf '%s\n' "$@" | jq -R -s --arg p "$path" '
    { Parameters: [ split("\n")[] | select(length > 0) | capture("^(?<k>[^=]+)=(?<v>.*)$") | { Name: ($p + .k), Value: .v, Type: "String" } ] }
  ' >"${FAKE_SSM_DIR}/$(printf '%s' "$path" | tr '/' '_').json"
}

api_env='{"AWS_REGION":"ap-northeast-1","APP_ENV":"dev","DB_SECRET_ARN":"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000","PORT":"8080"}'
worker_env='{"AWS_REGION":"ap-northeast-1","APP_ENV":"dev","METRICS_NAMESPACE":"Example/dev"}'
api_scaling='{"min_replicas":2,"max_replicas":10,"cpu_target_percent":60,"requests_per_target":300,"streams_per_replica":100,"region":"ap-northeast-1","alb_arn_suffix":"app/example-dev-alb/0123456789abcdef","target_group_arn_suffix":"targetgroup/example-dev-alb-api/0123456789ab"}'
worker_scaling='{"min_replicas":2,"max_replicas":6,"backlog_per_replica":25000,"region":"ap-northeast-1","metric_namespace":"Example/dev","metric_name":"StreamBacklogMax","dimension_name":"Env","dimension_value":"dev"}'

write_fixtures() {
  fixture /example/dev/eks-cluster/ \
    "contract_version=${1:-1}" cluster_name=example-dev "service_cidr=172.20.0.0/16" app_namespace=app \
    api_service_account=api worker_service_account=worker \
    cluster_endpoint=https://ABCDEF0123456789.gr7.ap-northeast-1.eks.amazonaws.com cluster_ca_data=Y2VydGlmaWNhdGU= \
    cluster_sg_id=sg-0aaaaaaa00000007
  fixture /example/dev/application/ \
    app_port=8080 "vpc_cidr=10.10.0.0/16" \
    api_target_group_arn=arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/example-dev-alb-api/0123456789ab \
    api_image_repository=111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api \
    worker_image_repository=111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-worker \
    "api_environment_json=${api_env}" "worker_environment_json=${worker_env}" \
    "api_scaling_json=${api_scaling}" "worker_scaling_json=${worker_scaling}"
}

# ---- 2. render ----

# Prints the line count of $2 in rendered file $1; fails the check when it is not $3 (default: at least 1).
expect() {
  local file="$1" pattern="$2" want="${3:-}" n
  n="$(grep -cF -- "$pattern" "$file" || true)"
  if [ -n "$want" ]; then
    [ "$n" -eq "$want" ] || fail "$(basename "$file"): expected ${want} line(s) with '${pattern}', found ${n}"
  else
    [ "$n" -ge 1 ] || fail "$(basename "$file"): no line with '${pattern}'"
  fi
}

# Same as expect, but the whole line without its indentation must equal $2 (kind: Service must not match
# kind: ServiceAccount, serviceAccountName: api must not match serviceAccountName: api-sa).
expect_line() {
  local file="$1" line="$2" want="$3" n
  n="$(sed 's/^[[:space:]]*//' "$file" | grep -cxF -- "$line" || true)"
  [ "$n" -eq "$want" ] || fail "$(basename "$file"): expected ${want} line(s) equal to '${line}', found ${n}"
}

write_fixtures 1
for c in api worker; do
  if ! bash "$script" --project example --env dev --component "$c" --image-tag 1.2.3 --region ap-northeast-1 >"${work}/${c}.json" 2>"${work}/${c}.err"; then
    fail "values-from-ssm.sh failed for ${c}: $(cat "${work}/${c}.err")"
    continue
  fi
  helm lint "$chart" -f "${work}/${c}.json" >/dev/null 2>"${work}/${c}.lint" || fail "helm lint ${c}: $(cat "${work}/${c}.lint")"
  helm template "$c" "$chart" -n app -f "${work}/${c}.json" >"${work}/${c}.yaml" 2>"${work}/${c}.tpl" || fail "helm template ${c}: $(cat "${work}/${c}.tpl")"
done

api="${work}/api.yaml"
worker="${work}/worker.yaml"

# Pod Identity: the ServiceAccount name comes from eks-cluster, never from the release name.
expect_line "$api" "serviceAccountName: api" 1
expect_line "$worker" "serviceAccountName: worker" 1
expect "$api" "image: \"111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api:1.2.3\""
expect "$api" "value: \"arn:aws:secretsmanager:ap-northeast-1:111111111111:secret:rds!cluster-0000\""
expect "$worker" "value: \"Example/dev\""

# Load balancing: only the api has a Service and a TargetGroupBinding, without the networking block (design v4 §4).
expect "$api" "kind: TargetGroupBinding" 1
expect "$api" "apiVersion: elbv2.k8s.aws/v1beta1" 1
expect "$api" "targetGroupARN: \"arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/example-dev-alb-api/0123456789ab\""
expect "$api" "targetType: ip"
expect "$api" "networking:" 0
expect "$worker" "kind: TargetGroupBinding" 0
expect_line "$worker" "kind: Service" 0
expect_line "$api" "kind: Service" 1
expect "$api" "type: LoadBalancer" 0
expect "$api" "kind: Ingress" 0

# Scaling (design v4 §9).
expect "$api" "kind: ScaledObject" 1
expect "$api" "minReplicaCount: 2"
expect "$api" "maxReplicaCount: 10"
expect "$api" "metricName: \"RequestCountPerTarget\""
expect "$api" "dimensionValue: \"targetgroup/example-dev-alb-api/0123456789ab;app/example-dev-alb/0123456789abcdef\""
expect "$api" "metricName: \"ActiveConnectionCount\""
expect "$api" "metricType: Utilization"
# RequestCountPerTarget is per target already (Value); ActiveConnectionCount is spread over replicas (AverageValue).
expect_line "$api" "metricType: Value" 1
expect_line "$api" "metricType: AverageValue" 1
expect "$api" "value: \"60\""
expect "$api" "stabilizationWindowSeconds: 900"
expect "$worker" "metricName: \"StreamBacklogMax\""
expect "$worker" "namespace: \"Example/dev\""
expect "$worker" "targetMetricValue: \"25000\""
expect "$worker" "metricStat: \"Maximum\""
expect "$worker" "provider: aws"
expect "$worker" "replicas:" 0

# NetworkPolicy under DefaultDeny: DNS on the service CIDR .10 (UDP and TCP), ALB ingress for the api only.
expect "$api" "kind: NetworkPolicy" 1
expect "$api" "cidr: \"172.20.0.10/32\""
expect "$api" "protocol: UDP"
expect "$api" "port: 53" 2
expect "$api" "Ingress"
expect "$worker" "- Ingress" 0
expect "$api" "net.ipv4.tcp_keepalive_time"

# The chart refuses a namespace other than the one Pod Identity was set up for.
if helm template api "$chart" -n other -f "${work}/api.json" >/dev/null 2>&1; then
  fail "chart rendered into namespace other although eks-cluster says app"
fi

# ---- 3. canary ----

canary_arn=arn:aws:elasticloadbalancing:ap-northeast-1:111111111111:targetgroup/example-dev-alb-api-canary/fedcba9876543210
fixture /example/dev/loadbalancer/ "api_canary_target_group_arn=${canary_arn}"
if bash "$script" --project example --env dev --component api --image-tag 1.3.0 --region ap-northeast-1 --canary >"${work}/canary.json" 2>"${work}/canary.err"; then
  helm template api-canary "$chart" -n app -f "${work}/canary.json" >"${work}/canary.yaml" 2>"${work}/canary.tpl" || fail "helm template canary: $(cat "${work}/canary.tpl")"
  canary="${work}/canary.yaml"
  expect "$canary" "targetGroupARN: \"${canary_arn}\""
  expect "$canary" "dimensionValue: \"targetgroup/example-dev-alb-api-canary/fedcba9876543210;app/example-dev-alb/0123456789abcdef\""
  expect_line "$canary" "kind: ServiceAccount" 0
  expect_line "$canary" "serviceAccountName: api" 1
  expect "$canary" "image: \"111111111111.dkr.ecr.ap-northeast-1.amazonaws.com/example-api:1.3.0\""
else
  fail "values-from-ssm.sh --canary failed: $(cat "${work}/canary.err")"
fi
if bash "$script" --project example --env dev --component worker --image-tag 1.3.0 --region ap-northeast-1 --canary >/dev/null 2>&1; then
  fail "values-from-ssm.sh accepted --canary for the worker"
fi
fixture /example/dev/loadbalancer/ "api_canary_target_group_arn=example-dev-alb-api-canary"
if bash "$script" --project example --env dev --component api --image-tag 1.3.0 --region ap-northeast-1 --canary >/dev/null 2>&1; then
  fail "values-from-ssm.sh accepted a canary target group that is not a target group ARN"
fi

# ---- 4. the script refuses what it does not understand ----

write_fixtures 2
if bash "$script" --project example --env dev --component api --image-tag 1.2.3 --region ap-northeast-1 >/dev/null 2>&1; then
  fail "values-from-ssm.sh accepted contract_version 2"
fi
write_fixtures 1
jq '.Parameters |= map(select(.Name | endswith("/api_scaling_json") | not))' "${FAKE_SSM_DIR}/_example_dev_application_.json" >"${work}/tmp.json"
mv "${work}/tmp.json" "${FAKE_SSM_DIR}/_example_dev_application_.json"
if bash "$script" --project example --env dev --component api --image-tag 1.2.3 --region ap-northeast-1 >/dev/null 2>"${work}/missing.err"; then
  fail "values-from-ssm.sh accepted a missing api_scaling_json"
elif ! grep -q "application 沒有發布這些 key：api_scaling_json" "${work}/missing.err"; then
  fail "values-from-ssm.sh must name the missing key, it said: $(cat "${work}/missing.err")"
fi

write_fixtures 1
rm -f "${FAKE_SSM_DIR}/_example_dev_loadbalancer_.json"
fixture /example/dev/loadbalancer/ "alb_arn_suffix=app/example-dev-alb/0123456789abcdef"
if bash "$script" --project example --env dev --component api --image-tag 1.3.0 --region ap-northeast-1 --canary >/dev/null 2>"${work}/nocanary.err"; then
  fail "values-from-ssm.sh --canary accepted a loadbalancer without a canary"
elif ! grep -q "api_canary_target_group_arn" "${work}/nocanary.err"; then
  fail "values-from-ssm.sh --canary must name the missing key, it said: $(cat "${work}/nocanary.err")"
fi

if [ "$errors" -ne 0 ]; then
  echo "FAIL check-deploy-values：${errors} 個問題" >&2
  exit 1
fi
echo "OK check-deploy-values"
