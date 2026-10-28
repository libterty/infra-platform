#!/usr/bin/env bash
# Static check of the SSM contract between stacks. It reads HCL and tfvars only; it never runs terraform or touches AWS.
#
# Check 1: every "<stack>/<key>" a stack reads must be published by a stack that comes earlier in ORDER, as the same
#          kind (String or StringList). Keys computed from tfvars are compared as patterns: each ${...} is a wildcard,
#          and a read pattern is covered when a published pattern matches it with every wildcard replaced by "x".
# Check 2: within one env, the tfvars of all stacks agree on SHARED_CONFIG_KEYS, and `env` matches the file name.
#
# ORDER is read from stacks.sh, so there is one list. The HCL forms this script understands are in infra/README.md:
#   <stack>/ssm-outputs.tf  locals published_strings / published_lists: a map, or merge(...) of maps. Keys of those maps
#                           are published keys; a `{ for ... : "<pattern>" => ... }` argument publishes a pattern.
#                           Before the resources exist: comment lines "# planned_strings: k1 k2" / "# planned_lists: k".
#   <stack>/*.tf            every string literal "<stack>/<key>" whose first segment is a stack in ORDER is a read;
#                           inside a map or merge(...) assigned to a name ending in "lists" (ssm_input_lists,
#                           ssm_agent_lists, lists = ...) it is a StringList read, otherwise a String.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# tfvars keys that must hold the same value in every stack of an env (all of them come from common.tf).
SHARED_CONFIG_KEYS=(project env aws_region expected_account_id)

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

# shellcheck disable=SC2016 # awk code, expanded by awk, not by the shell.
# Shared awk helpers: string literals (with ${...} interpolation that may hold nested quotes) and their pattern form.
AWK_LIB='
  # End index of the string literal that opens at i (the closing quote).
  function str_end(s, i,   j, ch, depth) {
    depth = 0
    for (j = i + 1; j <= length(s); j++) {
      ch = substr(s, j, 1)
      if (ch == "\\") { j++; continue }
      if (depth == 0 && ch == "\"") return j
      if (ch == "$" && substr(s, j + 1, 1) == "{") { depth++; j++; continue }
      if (depth > 0 && ch == "\"") { j = str_end(s, j); continue }
      if (depth > 0 && ch == "{") depth++
      if (depth > 0 && ch == "}") depth--
    }
    return length(s) + 1
  }
  # The literal with every ${...} replaced by *.
  function pattern(t,   out, j, ch, depth) {
    out = ""; depth = 0
    for (j = 1; j <= length(t); j++) {
      ch = substr(t, j, 1)
      if (depth == 0 && ch == "$" && substr(t, j + 1, 1) == "{") { depth = 1; j++; out = out "*"; continue }
      if (depth > 0) {
        if (ch == "\"") { j = str_end(t, j); continue }
        if (ch == "{") depth++
        if (ch == "}") depth--
        continue
      }
      out = out ch
    }
    return out
  }
'

# Print "<key-or-pattern> <S|L>" for every key a stack publishes. $1=stack
published_keys() {
  local f="${root}/$1/ssm-outputs.tf"
  [ -f "$f" ] || return 0
  awk "$AWK_LIB"'
    /^[[:space:]]*#[[:space:]]*planned_(strings|lists):/ {
      k = ($0 ~ /planned_strings:/) ? "S" : "L"
      sub(/^[^:]*:/, "")
      for (i = 1; i <= NF; i++) print $i, k
      next
    }
    !inblk {
      if (!match($0, /^[[:space:]]*published_(strings|lists)[[:space:]]*=/)) next
      kind = ($0 ~ /published_strings/) ? "S" : "L"
      line = substr($0, RSTART + RLENGTH); inblk = 1; sp = 0; started = 0
    }
    inblk {
      if (line == "") line = $0
      n = length(line)
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (c == "#" || (c == "/" && substr(line, i + 1, 1) == "/")) break
        if (c == "\"") {
          e = str_end(line, i)
          tok = substr(line, i + 1, e - i - 1)
          i = e
          rest = substr(line, e + 1); sub(/^[[:space:]]+/, "", rest)
          if (sp > 0 && hold[sp] && substr(rest, 1, 2) == "=>") print pattern(tok), kind
          continue
        }
        if (c == "(" || c == "{" || c == "[") {
          sp++; st[sp] = c; started = 1
          # A map whose keys are published: the value itself, or a direct argument of merge(...).
          hold[sp] = (c == "{" && (sp == 1 || (sp == 2 && st[1] == "(")))
          continue
        }
        if (c == ")" || c == "}" || c == "]") {
          sp--
          if (started && sp == 0) { inblk = 0; break }
          continue
        }
        if (c ~ /[a-z_]/ && (i == 1 || substr(line, i - 1, 1) !~ /[A-Za-z0-9_.]/)) {
          j = i
          while (j <= n && substr(line, j, 1) ~ /[A-Za-z0-9_]/) j++
          ident = substr(line, i, j - i)
          rest = substr(line, j); sub(/^[[:space:]]+/, "", rest)
          if (sp > 0 && hold[sp] && substr(rest, 1, 1) == "=" && substr(rest, 2, 1) !~ /[=>]/) print ident, kind
          i = j - 1
        }
      }
      if (!started) inblk = 0
      line = ""
    }
  ' "$f"
}

# Print "<file>:<line> <publisher> <key-or-pattern> <S|L>" for every read in a stack. $1=stack
read_keys() {
  local dir="${root}/$1" f
  for f in "$dir"/*.tf; do
    [ -f "$f" ] || continue
    awk -v stacks=" ${order[*]} " -v file="$1/$(basename "$f")" "$AWK_LIB"'
      /^[[:space:]]*(#|\/\/)/ { next }
      {
        # A StringList map runs from "<name>lists = {" or "<name>lists = merge(" until its brackets close again.
        if (!inlist && match($0, /[a-z0-9_]*lists[[:space:]]*=[[:space:]]*(\{|merge\()/)) { inlist = 1; ldepth = 0 }
        line_kind = inlist ? "L" : "S"
        if (inlist) {
          bare = $0; gsub(/"[^"]*"/, "", bare)
          ldepth += gsub(/[({]/, "", bare) - gsub(/[)}]/, "", bare)
          if (ldepth <= 0) inlist = 0
        }
        n = length($0)
        for (i = 1; i <= n; i++) {
          c = substr($0, i, 1)
          if (c == "#" || (c == "/" && substr($0, i + 1, 1) == "/")) break
          if (c != "\"") continue
          e = str_end($0, i)
          tok = pattern(substr($0, i + 1, e - i - 1))
          i = e
          if (tok !~ /^[a-z][a-z0-9-]*\/[a-z0-9_*]+$/) continue
          split(tok, p, "/")
          if (index(stacks, " " p[1] " ") == 0) continue
          print file ":" FNR, p[1], p[2], line_kind
        }
      }
    ' "$f"
  done
}

# True when read key $1 is covered by published key or pattern $2 (patterns use * for each ${...}).
covers() {
  local read="$1" pub="$2"
  if [[ "$pub" != *"*"* ]]; then
    [ "$read" = "$pub" ]
    return
  fi
  local instance="${read//\*/x}" re="^${pub//\*/[a-z0-9_]+}\$"
  [[ "$instance" =~ $re ]]
}

# Check 1: publishers, built once as "<stack> <key-or-pattern> <kind>" lines.
published=""
reads_total=0
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
  while read -r where publisher key kind; do
    [ -n "$where" ] || continue
    reads_total=$((reads_total + 1))
    ref="${publisher}/${key}"
    publisher_pos="$(position "$publisher")"
    if [ "$publisher_pos" -ge "$consumer_pos" ]; then
      fail "${where}: 讀 ${ref}，但 ${publisher} 在 ORDER 裡排在 ${stack} 之後（或就是自己），apply 時還沒有值"
      continue
    fi
    same=""
    other=""
    while read -r p_stack p_key p_kind; do
      [ "$p_stack" = "$publisher" ] || continue
      covers "$key" "$p_key" || continue
      if [ "$p_kind" = "$kind" ]; then same=1; else other="$p_kind"; fi
    done <<<"$published"
    [ -n "$same" ] && continue
    if [ -n "$other" ]; then
      fail "${where}: 讀 ${ref} 的型別（${kind}）跟 ${publisher} 發布的型別（${other}）不同；S 是 strings、L 是 lists"
    else
      fail "${where}: 讀 ${ref}，但 ${publisher}/ssm-outputs.tf 沒有發布這個 key，也沒有涵蓋它的樣式（* 代表 \${...}）"
    fi
  done < <(read_keys "$stack")
done

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
echo "OK check-ssm-contract：${#order[@]} 個 stack，${reads_total} 個讀取，${#envs[@]} 個 env"
