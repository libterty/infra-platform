#!/usr/bin/env bash
# Check that the template still works once it is copied out and pointed at the private registry: copy
# templates/project-infra/infra to a temp dir, rewrite its sources with template-to-registry.sh, then
# terraform init -backend=false and validate every stack against the published module versions.
#
# Usage:
#   scripts/check-template-registry.sh <host>/<namespace>
#
# Needs a token for the registry host (terraform login, or TF_TOKEN_<host>). Never touches AWS: AWS_* variables are
# cleared and nothing runs plan, apply or a backend. Prints a markdown table of the resolved module versions, and
# appends it to $GITHUB_STEP_SUMMARY when that is set.
#
# Exit status: 0 every stack passed, 1 bad input, 2 a stack failed init or validate.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

[ "$#" -eq 1 ] || { sed -n '6,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 1; }
registry="$1"

# Same as validate.sh: no AWS session from the environment or local config can reach terraform.
while IFS= read -r v; do unset "$v"; done < <(env | sed -n 's/^\(AWS_[A-Za-z0-9_]*\)=.*/\1/p')
export AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null
export TF_IN_AUTOMATION=1
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-${repo_root}/.cache/plugins}"
export TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true
mkdir -p "$TF_PLUGIN_CACHE_DIR"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -C "$repo_root" ls-files -z -- templates/project-infra/infra | (cd "$repo_root" && xargs -0 tar -cf -) | tar -xf - -C "$work"
tf_dir="${work}/templates/project-infra/infra/terraform"

"${repo_root}/scripts/template-to-registry.sh" "$registry" "$tf_dir"

failed=0
for d in "$tf_dir"/*/; do
  stack="$(basename "$d")"
  if terraform -chdir="$d" init -backend=false -input=false -lockfile=readonly -no-color >"${work}/${stack}.log" 2>&1 &&
    terraform -chdir="$d" validate -no-color >>"${work}/${stack}.log" 2>&1; then
    echo "ok   ${stack}"
  else
    echo "FAIL ${stack}" >&2
    sed 's/^/  /' "${work}/${stack}.log" >&2
    failed=1
  fi
done

summary="${work}/summary.md"
{
  echo "### Template against ${registry}"
  echo
  echo "| module | version | stacks |"
  echo "|---|---|---|"
  for d in "$tf_dir"/*/; do
    mj="${d}.terraform/modules/modules.json"
    [ -f "$mj" ] || continue
    jq -r --arg stack "$(basename "$d")" '.Modules[] | select(.Version) | "\(.Source | split("/")[2])\t\(.Version)\t\($stack)"' "$mj"
  done | sort | awk -F'\t' '
    { key = $1 "\t" $2; if (!(key in seen)) { order[++n] = key; seen[key] = $3 } else if (index(" " seen[key] " ", " " $3 " ") == 0) { seen[key] = seen[key] " " $3 } }
    END { for (i = 1; i <= n; i++) { split(order[i], a, "\t"); print "| `" a[1] "` | " a[2] " | " seen[order[i]] " |" } }'
  echo
  if [ "$failed" -eq 0 ]; then echo "All stacks passed init and validate."; else echo "**Some stacks failed; see the job log.**"; fi
} >"$summary"
cat "$summary"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$summary" >>"$GITHUB_STEP_SUMMARY"
fi

[ "$failed" -eq 0 ] || exit 2
