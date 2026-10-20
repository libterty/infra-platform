#!/usr/bin/env bash
# Static check of the SSM contract between stacks. It reads HCL and tfvars only; it never runs terraform or touches AWS.
#
# Check 1: every "<stack>/<key>" a stack reads must be published by a stack that comes earlier in ORDER, as the same
#          kind (String or StringList). Tree B keys ("infra/<key>") must be published by the bridge stack.
# Check 2: within one env, the tfvars of all stacks agree on SHARED_CONFIG_KEYS, and `env` matches the file name.
#
# ORDER is read from stacks.sh, so there is one list. The HCL formats this script understands are in infra/README.md:
#   <stack>/ssm-inputs.tf   locals ssm_input_strings / ssm_input_lists (tree A), shared_input_strings / shared_input_lists
#                           (tree B), each a multi-line map of  local_name = "<stack>/<key>"
#   <stack>/ssm-outputs.tf  locals published_strings / published_lists, each a map whose keys are the published keys,
#                           or, before the resources exist, comment lines "# planned_strings: k1 k2" / "# planned_lists: k"
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# tfvars keys that must hold the same value in every stack of an env. A stack that does not set a key is skipped, so
# bastion_enabled is compared between network (which opens the paths) and operation (which creates the instance), and
# guardrail_cross_region_profile_id between iam (which grants it) and agent (which uses it).
SHARED_CONFIG_KEYS=(project env aws_region expected_account_id deploy_role_arn bastion_enabled guardrail_cross_region_profile_id)
# The stack that publishes tree B, and the stack segment tree B keys carry.
BRIDGE_STACK="bridge"
SHARED_SEGMENT="infra"

errors=0
fail() {
  echo "FAIL $*" >&2
  errors=$((errors + 1))
}

# ORDER=( ... ) must sit on one line of stacks.sh; it is parsed, not executed.
order_line="$(grep -E '^ORDER=\(.*\)[[:space:]]*$' "${root}/stacks.sh" || true)"
if [ -z "$order_line" ]; then
  echo "FAIL stacks.sh 找不到單行的 ORDER=(...)" >&2
  exit 1
fi
order_line="${order_line#ORDER=(}"
order_line="${order_line%)*}"
read -r -a order <<<"$order_line"
if [ "${#order[@]}" -eq 0 ]; then
  echo "FAIL stacks.sh 的 ORDER 是空的" >&2
  exit 1
fi

# Print the index of stack $1 in ORDER, or nothing when it is not there.
position() {
  local i
  for i in "${!order[@]}"; do
    if [ "${order[$i]}" = "$1" ]; then
      echo "$i"
      return 0
    fi
  done
  return 0
}

# Print "<key> <S|L>" for every key a stack publishes. $1=stack
published_keys() {
  local f="${root}/$1/ssm-outputs.tf"
  [ -f "$f" ] || return 0
  awk '
    function count(s, ch,   t) { t = s; return gsub(ch, "", t) }
    /^[[:space:]]*#[[:space:]]*planned_(strings|lists):/ {
      kind = ($0 ~ /planned_strings:/) ? "S" : "L"
      sub(/^[^:]*:/, "")
      for (i = 1; i <= NF; i++) print $i, kind
      next
    }
    /^[[:space:]]*(#|\/\/)/ { next }
    blk == "" {
      if (match($0, /^[[:space:]]*published_(strings|lists)[[:space:]]*=[[:space:]]*\{/)) {
        kind = ($0 ~ /published_strings/) ? "S" : "L"
        rest = substr($0, RSTART + RLENGTH)
        depth = 1 + count(rest, "\\{") - count(rest, "\\}")
        if (depth > 0) blk = kind
      }
      next
    }
    {
      if (depth == 1 && match($0, /^[[:space:]]*[a-z][a-z0-9_]*[[:space:]]*=/)) {
        k = substr($0, RSTART, RLENGTH); sub(/^[[:space:]]*/, "", k); sub(/[[:space:]]*=$/, "", k)
        print k, blk
      }
      depth += count($0, "\\{") - count($0, "\\}")
      if (depth <= 0) blk = ""
    }
  ' "$f"
}

# Print "<A|B> <stack> <key> <S|L>" for every key a stack reads. $1=stack
read_keys() {
  local f="${root}/$1/ssm-inputs.tf"
  [ -f "$f" ] || return 0
  awk '
    function emit(s,   m) {
      while (match(s, /"[a-z][a-z0-9-]*\/[a-z][a-z0-9_]*"/)) {
        m = substr(s, RSTART + 1, RLENGTH - 2)
        split(m, p, "/")
        print tree, p[1], p[2], kind
        s = substr(s, RSTART + RLENGTH)
      }
    }
    /^[[:space:]]*(#|\/\/)/ { next }
    blk == "" {
      if (match($0, /^[[:space:]]*(ssm_input|shared_input)_(strings|lists)[[:space:]]*=[[:space:]]*\{/)) {
        head = substr($0, RSTART, RLENGTH)
        tree = (head ~ /shared_input/) ? "B" : "A"
        kind = (head ~ /_strings/) ? "S" : "L"
        rest = substr($0, RSTART + RLENGTH)
        if (rest ~ /\}/) emit(rest); else blk = 1
      }
      next
    }
    /^[[:space:]]*\}/ { blk = ""; next }
    { emit($0) }
  ' "$f"
}

# Print the value of tfvars key $2 in file $1 (first assignment, quotes removed); nothing when absent.
tfvar() {
  awk -v key="$2" '
    /^[[:space:]]*(#|\/\/)/ { next }
    match($0, "^[[:space:]]*" key "[[:space:]]*=") {
      v = substr($0, RSTART + RLENGTH)
      sub(/[[:space:]]+(#|\/\/).*$/, "", v)
      gsub(/^[[:space:]]+|[[:space:]]+$|"/, "", v)
      print v
      exit
    }
  ' "$1"
}

# Check 1: publishers, built once as "<stack> <key> <kind>" lines.
published=""
for stack in "${order[@]}"; do
  if [ ! -d "${root}/${stack}" ]; then
    fail "stacks.sh 的 ORDER 列了 ${stack}，但目錄 ${stack}/ 不存在"
    continue
  fi
  while read -r key kind; do
    [ -n "$key" ] || continue
    published+="${stack} ${key} ${kind}"$'\n'
  done < <(published_keys "$stack")
done

for stack in "${order[@]}"; do
  [ -d "${root}/${stack}" ] || continue
  consumer_pos="$(position "$stack")"
  while read -r tree publisher key kind; do
    [ -n "$tree" ] || continue
    ref="${publisher}/${key}"
    if [ "$tree" = "B" ]; then
      if [ "$publisher" != "$SHARED_SEGMENT" ]; then
        fail "${stack}/ssm-inputs.tf: 樹 B 的 key ${ref} 的前綴必須是 ${SHARED_SEGMENT}/"
        continue
      fi
      publisher="$BRIDGE_STACK"
    fi
    publisher_pos="$(position "$publisher")"
    if [ -z "$publisher_pos" ]; then
      fail "${stack}/ssm-inputs.tf: 讀 ${ref}，但 ${publisher} 不在 stacks.sh 的 ORDER 裡"
      continue
    fi
    if [ "$publisher_pos" -ge "$consumer_pos" ]; then
      fail "${stack}/ssm-inputs.tf: 讀 ${ref}，但 ${publisher} 在 ORDER 裡排在 ${stack} 之後（或就是自己），apply 時還沒有值"
      continue
    fi
    if ! grep -Fqx "${publisher} ${key} ${kind}" <<<"$published"; then
      other="S"
      [ "$kind" = "S" ] && other="L"
      if grep -Fqx "${publisher} ${key} ${other}" <<<"$published"; then
        fail "${stack}/ssm-inputs.tf: 讀 ${ref} 的型別（${kind}）跟 ${publisher} 發布的型別（${other}）不同；S 是 strings、L 是 lists"
      else
        fail "${stack}/ssm-inputs.tf: 讀 ${ref}，但 ${publisher}/ssm-outputs.tf 沒有發布這個 key"
      fi
    fi
  done < <(read_keys "$stack")
done

# Check 2: tfvars shared keys. Envs are the union of envs/*.tfvars over all stacks.
envs=()
while IFS= read -r e; do envs+=("$e"); done < <(
  for stack in "${order[@]}"; do
    for f in "${root}/${stack}"/envs/*.tfvars; do
      [ -f "$f" ] && basename "$f" .tfvars
    done
  done | sort -u
)

for e in ${envs[@]+"${envs[@]}"}; do
  for key in "${SHARED_CONFIG_KEYS[@]}"; do
    first_stack=""
    first_value=""
    for stack in "${order[@]}"; do
      f="${root}/${stack}/envs/${e}.tfvars"
      [ -f "$f" ] || continue
      value="$(tfvar "$f" "$key")"
      [ -n "$value" ] || continue
      if [ "$key" = "env" ] && [ "$value" != "$e" ]; then
        fail "${stack}/envs/${e}.tfvars: env = \"${value}\"，但檔名是 ${e}"
      fi
      if [ -z "$first_stack" ]; then
        first_stack="$stack"
        first_value="$value"
      elif [ "$value" != "$first_value" ]; then
        fail "env ${e} 的 ${key} 不一致：${first_stack} 是 \"${first_value}\"，${stack} 是 \"${value}\""
      fi
    done
  done
done

if [ "$errors" -ne 0 ]; then
  echo "FAIL check-ssm-contract：${errors} 個問題" >&2
  exit 1
fi
echo "OK check-ssm-contract：${#order[@]} 個 stack，${#envs[@]} 個 env"
