#!/usr/bin/env bash
# Point a copied template at the private registry: every source = "../../../../../modules/<module>" becomes
# source = "<registry>/<module>/aws" plus version = "~> <MAJOR>.<MINOR>.0".
#
# Usage:
#   scripts/template-to-registry.sh <host>/<namespace> <terraform-dir>
#   e.g. scripts/template-to-registry.sh app.terraform.io/acme /path/to/project/infra/terraform
#
# The constraint comes from this repo's .release-please-manifest.json, so it follows the current release of each
# module: patch versions are picked up by terraform init, the next MINOR is not (0.x MINOR may break, design 3.5).
# Files are rewritten in place and then terraform fmt'ed. Run it on a copy you can review with git diff.
#
# Exit status: 0 done, 1 bad input or refused before any change.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
manifest="${repo_root}/.release-please-manifest.json"

die() {
  echo "template-to-registry: $*" >&2
  exit 1
}

[ "$#" -eq 2 ] || { sed -n '5,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 1; }
registry="$1"
dir="$2"

registry_re='^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+/[A-Za-z0-9][A-Za-z0-9_-]*$'
[[ "$registry" =~ $registry_re ]] || die "registry must look like <host>/<namespace> with a lowercase host, for example app.terraform.io/acme: ${registry}"
[ -d "$dir" ] || die "not a directory: ${dir}"
command -v jq >/dev/null 2>&1 || die "needs jq"
command -v terraform >/dev/null 2>&1 || die "needs terraform (for terraform fmt)"

# <module> TAB <constraint>, one line per module in the manifest.
constraints="$(mktemp)"
trap 'rm -f "$constraints"' EXIT
jq -r 'to_entries[]
  | select(.key | startswith("modules/"))
  | (.value | split(".")) as $v
  | "\(.key | ltrimstr("modules/"))\t~> \($v[0]).\($v[1]).0"' "$manifest" >"$constraints" ||
  die "cannot read ${manifest}"

# Collect and check every file before changing any of them.
files=()
while IFS= read -r -d '' f; do
  [ ! -L "$f" ] || die "${f} is a symlink; refusing to rewrite through it"
  files+=("$f")
done < <(find "$dir" -name '*.tf' -not -path '*/.terraform*' -print0)
[ "${#files[@]}" -gt 0 ] || die "no .tf files under ${dir}"

# The module names used must all be in the manifest; an unknown one would get no version line.
unknown="$({ grep -hoE '^[[:space:]]*source[[:space:]]*=[[:space:]]*"(\.\./){5}modules/[a-z0-9-]+"' "${files[@]}" || true; } |
  sed -E 's#.*/modules/##; s#"$##' | sort -u | while IFS= read -r m; do
    grep -q "^${m}	" "$constraints" || echo "$m"
  done)"
[ -z "$unknown" ] || die "modules not in ${manifest}: $(echo "$unknown" | tr '\n' ' ')"

changed=0
for f in "${files[@]}"; do
  out="$(mktemp)"
  awk -v reg="$registry" -v table="$constraints" '
    BEGIN {
      while ((getline line < table) > 0) {
        split(line, a, "\t")
        want[a[1]] = a[2]
      }
      close(table)
    }
    match($0, /^[[:space:]]*source[[:space:]]*=[[:space:]]*"\.\.\/\.\.\/\.\.\/\.\.\/\.\.\/modules\/[a-z0-9-]+"/) {
      m = substr($0, RSTART, RLENGTH)
      sub(/^.*\/modules\//, "", m)
      sub(/"$/, "", m)
      indent = $0
      sub(/[^[:space:]].*$/, "", indent)
      print indent "source  = \"" reg "/" m "/aws\""
      print indent "version = \"" want[m] "\""
      n++
      next
    }
    { print }
    END { exit n == 0 ? 2 : 0 }
  ' "$f" >"$out" && rc=0 || rc=$?
  case "$rc" in
    0) cat "$out" >"$f"; changed=$((changed + 1)) ;;
    2) ;;
    *) rm -f "$out"; die "awk failed on ${f}" ;;
  esac
  rm -f "$out"
done

terraform fmt -recursive "$dir" >/dev/null
left="$(grep -rlE --include='*.tf' '"(\.\./){5}modules/' "$dir" || true)"
[ -z "$left" ] || die "relative module sources left after the rewrite: ${left}"
echo "rewrote ${changed} file(s) under ${dir}"
