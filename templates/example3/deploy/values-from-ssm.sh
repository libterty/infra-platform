#!/usr/bin/env bash
# Build the Helm values of one workload (api or worker) from the SSM deploy contract (design v4 §8.1) and print them
# as JSON on stdout (JSON is valid YAML, so `helm upgrade -f` reads it). CI runs it before every deploy:
#
#   values-from-ssm.sh --project example --env dev --component api --image-tag 1.2.3 > api.json
#   helm upgrade --install api deploy/charts/app -n "$(jq -r .namespace api.json)" -f api.json --atomic
#
# The identity running it needs ssm:GetParametersByPath on /<project>/<env>/eks-cluster/ and
# /<project>/<env>/application/. It reads no secret: the environment carries secret ARNs only (design v4 §8.2).
# Needs the AWS CLI and jq.
set -euo pipefail

# Keys this script reads, one line each: application/tests/check-deploy-values.sh compares them with the producers.
EKS_CLUSTER_KEYS=(contract_version service_cidr app_namespace api_service_account worker_service_account)
APPLICATION_KEYS=(app_port vpc_cidr api_target_group_arn api_image_repository worker_image_repository api_environment_json worker_environment_json api_scaling_json worker_scaling_json)

# eks-cluster contract versions this script understands.
SUPPORTED_EKS_CONTRACT_VERSIONS=(1)

usage() {
  cat >&2 <<'USAGE'
用法：values-from-ssm.sh --project <project> --env <env> --component <api|worker> --image-tag <tag> [--region <region>]

  --region  預設用 AWS_REGION
USAGE
}

die() {
  echo "錯誤：$*" >&2
  exit 2
}

project=""
env_name=""
component=""
image_tag=""
region="${AWS_REGION:-}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project | --env | --component | --image-tag | --region)
      [ "$#" -ge 2 ] || die "$1 需要一個值"
      case "$1" in
        --project) project="$2" ;;
        --env) env_name="$2" ;;
        --component) component="$2" ;;
        --image-tag) image_tag="$2" ;;
        --region) region="$2" ;;
      esac
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      die "不認得的參數：$1"
      ;;
  esac
done

[[ "$project" =~ ^[a-z][a-z0-9-]{1,15}$ ]] || die "--project 格式不對：${project}"
[[ "$env_name" =~ ^[a-z][a-z0-9]{1,11}$ ]] || die "--env 格式不對：${env_name}"
[[ "$component" =~ ^(api|worker)$ ]] || die "--component 只能是 api 或 worker：${component}"
[[ "$image_tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || die "--image-tag 不是合法的 image tag：${image_tag}"
[[ "$region" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]$ ]] || die "--region 或 AWS_REGION 格式不對：${region}"
command -v aws >/dev/null || die "找不到 aws CLI"
command -v jq >/dev/null || die "找不到 jq"

# Prints {"<key>": "<value>", ...} for the parameters under /<project>/<env>/<stack>/. The CLI follows NextToken itself.
read_stack() {
  local prefix="/${project}/${env_name}/$1/"
  aws ssm get-parameters-by-path --path "$prefix" --region "$region" --output json |
    jq --arg p "$prefix" '[.Parameters[] | {key: (.Name | ltrimstr($p)), value: .Value}] | from_entries'
}

# Fails with the missing key names; $1 = stack, $2 = JSON object, rest = required keys.
require_keys() {
  local stack="$1" json="$2" missing
  shift 2
  missing="$(jq -r --args '[$ARGS.positional[] as $k | select(has($k) | not) | $k] | join(", ")' "$@" <<<"$json")"
  [ -z "$missing" ] || die "${stack} 沒有發布這些 key：${missing}（先 apply ${stack}）"
}

eks="$(read_stack eks-cluster)"
app="$(read_stack application)"
require_keys eks-cluster "$eks" "${EKS_CLUSTER_KEYS[@]}"
require_keys application "$app" "${APPLICATION_KEYS[@]}"

version="$(jq -r .contract_version <<<"$eks")"
supported=0
for v in "${SUPPORTED_EKS_CONTRACT_VERSIONS[@]}"; do
  [ "$v" = "$version" ] && supported=1
done
[ "$supported" -eq 1 ] || die "eks-cluster/contract_version 是 ${version}，這支腳本只認得 ${SUPPORTED_EKS_CONTRACT_VERSIONS[*]}"

jq -n \
  --argjson eks "$eks" \
  --argjson app "$app" \
  --arg component "$component" \
  --arg tag "$image_tag" '
  # Cluster DNS is the .10 address of the service CIDR (EKS puts CoreDNS there); EKS service CIDRs are /12 to /24.
  def dns_cidr:
    split("/") as [$net, $bits]
    | if ($bits | tonumber) > 24 then error("service_cidr \(.) is smaller than /24") else . end
    | ($net | split(".")) as $o
    | "\($o[0]).\($o[1]).\($o[2]).10/32";
  {
    component: $component,
    namespace: $eks.app_namespace,
    image: { repository: $app["\($component)_image_repository"], tag: $tag },
    serviceAccount: { name: $eks["\($component)_service_account"], create: true },
    port: ($app.app_port | tonumber),
    env: ($app["\($component)_environment_json"] | fromjson),
    targetGroupArn: (if $component == "api" then $app.api_target_group_arn else "" end),
    scaling: ($app["\($component)_scaling_json"] | fromjson),
    networkPolicy: { vpcCidr: $app.vpc_cidr, dnsCidr: ($eks.service_cidr | dns_cidr) }
  }'
