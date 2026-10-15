#!/usr/bin/env bash
# Copy tagged modules into a customer repo and point its git:: sources at the copies.
#
# Usage:
#   scripts/vendor-modules.sh --url https://github.com/<org>/<repo>.git <target-repo> <module>=<tag> [<module>=<tag> ...]
#
# For each <module>=<tag>:
#   - the module is taken from this repo with `git archive <tag> modules/<module>` and written to
#     <target-repo>/vendor/modules/<module>/ (replacing an earlier copy);
#   - every .tf line in the target whose source is exactly
#     "git::<url>//modules/<module>?ref=<tag>" is rewritten to the relative path of that copy;
#   - vendor/modules/VERSIONS gets one line: <module> <tag> <commit>.
# Lines that point at the same module with another ref are left alone and listed; the exit status is then 3.
# Only this direction is handled. Turning the template's relative paths into git:: sources is a manual step
# (docs/guides/consuming-modules.md).
#
# Exit status: 0 done, 1 bad input or refused before any change, 3 done but some lines were left unrewritten.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

die() {
  echo "vendor-modules: $*" >&2
  exit 1
}

usage() {
  sed -n '4,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 1
}

url=""
if [ "${1:-}" = "--url" ]; then
  [ "$#" -ge 2 ] || usage
  url="$2"
  shift 2
fi
[ -n "$url" ] || usage
[ "$#" -ge 2 ] || usage

# [[ =~ ]] matches the whole string; grep would accept a value with a valid line and an invalid one.
url_re='^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$'
name_re='^[a-z][a-z0-9-]*$'
tag_re='^[a-z][a-z0-9-]*-v[0-9]+\.[0-9]+\.[0-9]+$'

# Only the https form from design section 3.3 is rewritten. The character set keeps the value safe inside awk -v.
[[ "$url" =~ $url_re ]] || die "--url must look like https://github.com/<org>/<repo>.git: ${url}"

target_arg="$1"
shift

# Module names come from the modules/ directory of this repo, never from a hand-written list.
known_modules=()
for d in "${repo_root}"/modules/*/; do
  [ -d "$d" ] || continue
  known_modules+=("$(basename "$d")")
done
[ "${#known_modules[@]}" -gt 0 ] || die "no modules found under ${repo_root}/modules"

is_known_module() {
  local m
  for m in "${known_modules[@]}"; do
    [ "$m" = "$1" ] && return 0
  done
  return 1
}

# Validate every <module>=<tag> before touching anything.
names=()
tags=()
commits=()
for pair in "$@"; do
  case "$pair" in
    *=*) ;;
    *) die "expected <module>=<tag>, got: ${pair}" ;;
  esac
  name="${pair%%=*}"
  tag="${pair#*=}"

  [[ "$name" =~ $name_re ]] || die "module name must match ^[a-z][a-z0-9-]*\$: ${name}"
  is_known_module "$name" || die "unknown module (not a directory under modules/): ${name}"
  [[ "$tag" =~ $tag_re ]] || die "tag must be <module>-v<MAJOR>.<MINOR>.<PATCH>: ${tag}"
  [ "${tag%-v*}" = "$name" ] || die "tag ${tag} does not belong to module ${name}"

  commit="$(git -C "$repo_root" rev-parse --verify --quiet "refs/tags/${tag}^{commit}")" || die "tag not found in ${repo_root}: ${tag}"
  [ "$(git -C "$repo_root" cat-file -t "${commit}:modules/${name}" 2>/dev/null || true)" = "tree" ] ||
    die "modules/${name} does not exist at ${tag}"

  # Mode 120000 is a symlink and 160000 a submodule; neither may be copied into a customer repo.
  if git -C "$repo_root" ls-tree -r "$commit" -- "modules/${name}" | awk '$1 == "120000" || $1 == "160000" { found = 1 } END { exit !found }'; then
    die "modules/${name} at ${tag} contains a symlink or submodule; refusing to vendor it"
  fi

  for n in ${names[@]+"${names[@]}"}; do
    [ "$n" = "$name" ] && die "module given twice: ${name}"
  done
  names+=("$name")
  tags+=("$tag")
  commits+=("$commit")
done

# The target must be the top of a clean git repo, so every change below can be reviewed and reverted with git.
[ -d "$target_arg" ] || die "target is not a directory: ${target_arg}"
target="$(cd "$target_arg" && pwd -P)"
top="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" || die "target is not a git repository: ${target}"
top="$(cd "$top" && pwd -P)"
[ "$top" = "$target" ] || die "target must be the top of its git repository (${top}), not a subdirectory"
[ "$target" != "$repo_root" ] || die "target must not be this repository"
[ -z "$(git -C "$target" status --porcelain --untracked-files=all)" ] || die "target has uncommitted changes; commit or stash them first"

# vendor/ and vendor/modules/ must be real directories inside the target, never symlinks leading out of it.
for p in vendor vendor/modules; do
  if [ -L "${target}/${p}" ]; then
    die "${target}/${p} is a symlink; refusing to write through it"
  fi
done
mkdir -p "${target}/vendor/modules"
vendor_dir="$(cd "${target}/vendor/modules" && pwd -P)"
[ "$vendor_dir" = "${target}/vendor/modules" ] || die "vendor/modules resolves outside the target: ${vendor_dir}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Tracked .tf files of the target, excluding the vendored copies themselves.
tf_files=()
while IFS= read -r -d '' f; do
  case "$f" in
    vendor/modules/*) continue ;;
  esac
  tf_files+=("$f")
done < <(git -C "$target" ls-files -z -- '*.tf')

left_alone=0
i=0
while [ "$i" -lt "${#names[@]}" ]; do
  name="${names[$i]}"
  tag="${tags[$i]}"
  commit="${commits[$i]}"
  i=$((i + 1))

  rm -rf "${work:?}/extract"
  mkdir -p "${work}/extract"
  git -C "$repo_root" archive --format=tar "$commit" -- "modules/${name}" | tar -x -C "${work}/extract" -f -
  # Second check on what was actually extracted.
  if [ -n "$(find "${work}/extract" -type l -print -quit)" ]; then
    die "modules/${name} at ${tag} extracted a symlink; refusing to vendor it"
  fi

  dest="${vendor_dir}/${name}"
  rm -rf "${dest:?}"
  mv "${work}/extract/modules/${name}" "$dest"

  want="git::${url}//modules/${name}?ref=${tag}"
  prefix="git::${url}//modules/${name}?ref="
  rewritten=0
  for f in ${tf_files[@]+"${tf_files[@]}"}; do
    dir="$(dirname "$f")"
    if [ "$dir" = "." ]; then
      rel="./vendor/modules/${name}"
    else
      ups="$(printf '%s\n' "$dir" | awk -F/ '{ s = ""; for (k = 1; k <= NF; k++) s = s "../"; print s }')"
      rel="${ups}vendor/modules/${name}"
    fi

    # Exact string comparison of the quoted source value; nothing from the input is used as a regex.
    awk -v want="$want" -v prefix="$prefix" -v repl="$rel" -v file="$f" -v report="${work}/report" -v count="${work}/count" '
      match($0, /^[[:space:]]*source[[:space:]]*=[[:space:]]*"[^"]*"/) {
        head = substr($0, RSTART, RLENGTH)
        tail = substr($0, RSTART + RLENGTH)
        value = head
        sub(/^[^"]*"/, "", value)
        sub(/"$/, "", value)
        if (value == want) {
          lead = head
          sub(/"[^"]*"$/, "", lead)
          print lead "\"" repl "\"" tail
          n++
          next
        }
        if (index(value, prefix) == 1) {
          print file ":" FNR ": " value >> report
        }
      }
      { print }
      END { print n + 0 >> count }
    ' "${target}/${f}" >"${work}/out"
    if ! cmp -s "${work}/out" "${target}/${f}"; then
      cat "${work}/out" >"${target}/${f}"
    fi
  done
  if [ -f "${work}/count" ]; then
    rewritten="$(awk '{ s += $1 } END { print s + 0 }' "${work}/count")"
    rm -f "${work}/count"
  fi

  # One line per module; a later run for the same module replaces its line.
  versions="${vendor_dir}/VERSIONS"
  touch "$versions"
  awk -v m="$name" '$1 != m' "$versions" >"${work}/versions"
  printf '%s %s %s\n' "$name" "$tag" "$commit" >>"${work}/versions"
  sort "${work}/versions" >"$versions"

  echo "vendored ${name} ${tag} (${commit}) into vendor/modules/${name}; rewrote ${rewritten} source line(s)"
  if [ "$rewritten" -eq 0 ]; then
    echo "warning: no source line pointed at ${want}" >&2
  fi
done

if [ -s "${work}/report" ]; then
  echo "left unchanged (same module, different ref):" >&2
  sed 's/^/  /' "${work}/report" >&2
  left_alone=1
fi

if [ "$left_alone" -ne 0 ]; then
  exit 3
fi
