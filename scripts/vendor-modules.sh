#!/usr/bin/env bash
# Copy tagged modules into a customer repo and point its git:: or registry sources at the copies.
#
# Usage:
#   scripts/vendor-modules.sh [--url https://github.com/<org>/<repo>.git] [--registry <host>/<namespace>] <target-repo> <module>=<tag> [<module>=<tag> ...]
#   At least one of --url and --registry is required.
#
# For each <module>=<tag>:
#   - the module is taken from this repo with `git archive <tag> modules/<module>` and written to
#     <target-repo>/vendor/modules/<module>/ (replacing an earlier copy);
#   - with --url, every .tf line in the target whose source is exactly
#     "git::<url>//modules/<module>?ref=<tag>" is rewritten to the relative path of that copy;
#   - with --registry, every top-level module block whose source is "<host>/<namespace>/<module>/aws" and that
#     Terraform resolved to the tag's version gets its source rewritten the same way and its version line removed.
#     The resolved version is read from <stack>/${TF_DATA_DIR:-.terraform}/modules/modules.json, so run
#     `terraform init` in every stack first; a modules.json older than the .tf files next to it is ignored. Needs jq.
#     Blocks are found by brace depth counted on code only (strings, comments and heredoc bodies are skipped); a file
#     whose braces do not balance is refused;
#   - vendor/modules/VERSIONS gets one line: <module> <tag> <commit>.
# Lines that point at the same module with another ref, and registry blocks resolved to another version or not
# resolved at all, are left alone and listed; the exit status is then 3.
# Only this direction is handled. Changing the template's registry org or switching to git:: sources is a manual
# step (docs/guides/consuming-modules.md).
#
# Exit status: 0 done, 1 bad input or refused before any change, 3 done but some lines were left unrewritten.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

die() {
  echo "vendor-modules: $*" >&2
  exit 1
}

usage() {
  sed -n '4,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 1
}

url=""
registry=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --url | --registry)
      [ "$#" -ge 2 ] || usage
      if [ "$1" = "--url" ]; then url="$2"; else registry="$2"; fi
      shift 2
      ;;
    *) break ;;
  esac
done
[ -n "$url" ] || [ -n "$registry" ] || usage
[ "$#" -ge 2 ] || usage

# [[ =~ ]] matches the whole string; grep would accept a value with a valid line and an invalid one.
url_re='^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$'
registry_re='^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+/[A-Za-z0-9][A-Za-z0-9_-]*$'
data_dir_re='^\.?[A-Za-z0-9_][A-Za-z0-9._-]*$'
name_re='^[a-z][a-z0-9-]*$'
tag_re='^[a-z][a-z0-9-]*-v[0-9]+\.[0-9]+\.[0-9]+$'

# Only the https form from design section 3.3 is rewritten. The character sets keep the values safe inside awk -v.
if [ -n "$url" ]; then
  [[ "$url" =~ $url_re ]] || die "--url must look like https://github.com/<org>/<repo>.git: ${url}"
fi
data_dir="${TF_DATA_DIR:-.terraform}"
if [ -n "$registry" ]; then
  [[ "$registry" =~ $registry_re ]] || die "--registry must look like <host>/<namespace> with a lowercase host, for example app.terraform.io/acme: ${registry}"
  # A data dir relative to each stack, as Terraform uses it; an absolute or nested path would point every stack at one file.
  [[ "$data_dir" =~ $data_dir_re ]] || die "TF_DATA_DIR must be a single relative directory name such as .terraform-prod: ${data_dir}"
  command -v jq >/dev/null 2>&1 || die "--registry needs jq to read modules.json"
fi

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

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Tracked .tf files of the target, excluding the vendored copies themselves.
tf_files=()
while IFS= read -r -d '' f; do
  case "$f" in
    vendor/modules/*) continue ;;
    *$'\t'* | *$'\n'*) die "file name contains a tab or newline: ${f}" ;;
  esac
  # A symlinked .tf file could make the final write land outside the target.
  [ ! -L "${target}/${f}" ] || die "${f} is a symlink; refusing to rewrite through it"
  tf_files+=("$f")
done < <(git -C "$target" ls-files -z -- '*.tf')

# For --registry: what Terraform resolved in each directory, one line per root module call:
# <dir> TAB <key> TAB <source> TAB <version>. Read once here so a broken modules.json stops the run before anything
# is written. A missing modules.json, or one older than a .tf file next to it, contributes nothing, so the blocks in
# that directory are reported as not resolved.
resolved="${work}/resolved.tsv"
: >"$resolved"
if [ -n "$registry" ]; then
  while IFS= read -r dir; do
    mj="${target}/${dir}/${data_dir}/modules/modules.json"
    [ -f "$mj" ] && [ ! -L "$mj" ] || continue
    [ -z "$(find "${target}/${dir}" -maxdepth 1 -name '*.tf' -newer "$mj" -print -quit)" ] || continue
    # Nested calls have a dotted key; only the target's own module blocks are rewritten.
    jq -r --arg dir "$dir" '
      .Modules[]
      | select(.Version != null and .Key != "" and (.Key | contains(".") | not))
      | [$dir, .Key, (.Source | ascii_downcase), .Version] | @tsv
    ' "$mj" >>"$resolved" || die "cannot read ${mj}"
  done < <(for f in ${tf_files[@]+"${tf_files[@]}"}; do dirname "$f"; done | sort -u)
fi

# Registry rewrite. Pass 1 picks the top-level module blocks whose source is this module and whose resolved version
# is the tag's; pass 2 rewrites their source and drops their version line. Brace depth is counted on code only:
# string contents, # // /* */ comments and heredoc bodies are skipped. A file that does not end at depth 0 is refused.
# shellcheck disable=SC2016  # awk program, not shell
registry_awk='
  function code_of(s,    out, i, n, c, two, rest) {
    out = ""
    n = length(s)
    i = 1
    while (i <= n) {
      two = substr(s, i, 2)
      if (in_comment) {
        if (two == "*/") { in_comment = 0; i += 2 } else { i++ }
        continue
      }
      c = substr(s, i, 1)
      if (c == "\"") {
        i++
        while (i <= n) {
          c = substr(s, i, 1)
          if (c == "\\") { i += 2; continue }
          i++
          if (c == "\"") break
        }
        out = out "\"\""
        continue
      }
      if (c == "#" || two == "//") break
      if (two == "/*") { in_comment = 1; i += 2; continue }
      if (two == "<<") {
        rest = substr(s, i + 2)
        if (match(rest, /^-?[A-Za-z_][A-Za-z0-9_-]*/)) {
          heredoc = substr(rest, RSTART, RLENGTH)
          sub(/^-/, "", heredoc)
          break
        }
      }
      out = out c
      i++
    }
    return out
  }
  BEGIN {
    want = tolower(ENVIRON["VM_WANT"])
    want_version = ENVIRON["VM_VERSION"]
    dir = ENVIRON["VM_DIR"]
    file = ENVIRON["VM_FILE"]
    repl = ENVIRON["VM_REPL"]
    while ((getline line < ENVIRON["VM_RESOLVED"]) > 0) {
      split(line, a, "\t")
      if (a[1] == dir) { src[a[2]] = a[3]; ver[a[2]] = a[4] }
    }
    close(ENVIRON["VM_RESOLVED"])
  }
  function check_end() {
    if (depth != 0 || heredoc != "" || in_comment) {
      print "vendor-modules: cannot follow the block structure of " file " (unbalanced braces, or an unterminated heredoc or comment); run terraform fmt and check the file" > "/dev/stderr"
      bad = 1
      exit 1
    }
  }
  FNR == 1 {
    if (pass == 1) check_end()
    pass++
    depth = 0; heredoc = ""; in_comment = 0; cur = ""; start = 0
  }
  {
    line = $0
    if (heredoc != "") {
      code = ""
      t = line
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
      if (t == heredoc) heredoc = ""
      normal = 0
    } else {
      normal = !in_comment
      code = code_of(line)
    }

    is_source = 0
    is_version = 0
    if (normal && depth == 0 && code ~ /^[[:space:]]*module[[:space:]]+""[[:space:]]*\{/ && match(line, /^[[:space:]]*module[[:space:]]+"[^"]+"/)) {
      cur = substr(line, RSTART, RLENGTH)
      sub(/^[^"]*"/, "", cur)
      sub(/"$/, "", cur)
      start = FNR
    } else if (normal && depth == 1 && cur != "") {
      if (code ~ /^[[:space:]]*source[[:space:]]*=[[:space:]]*""/ && match(line, /^[[:space:]]*source[[:space:]]*=[[:space:]]*"[^"]*"/)) {
        head = substr(line, RSTART, RLENGTH)
        tail = substr(line, RSTART + RLENGTH)
        value = head
        sub(/^[^"]*"/, "", value)
        sub(/"$/, "", value)
        is_source = (tolower(value) == want)
      } else if (code ~ /^[[:space:]]*version[[:space:]]*=/) {
        is_version = 1
      }
    }

    if (pass == 1 && is_source) {
      if ((cur in ver) && src[cur] == want && ver[cur] == want_version) {
        hit[start] = 1
      } else if (cur in ver) {
        print file ":" FNR ": " value " (resolved to " ver[cur] ")" >> ENVIRON["VM_REPORT"]
      } else {
        print file ":" FNR ": " value " (not resolved: no modules.json in this directory, or it is older than the .tf files; run terraform init here)" >> ENVIRON["VM_REPORT"]
      }
    }
    if (pass == 2) {
      if (is_source && (start in hit)) {
        lead = head
        sub(/"[^"]*"$/, "", lead)
        print lead "\"" repl "\"" tail
        n++
      } else if (!(is_version && (start in hit))) {
        print line
      }
    }

    t = code
    depth += gsub(/\{/, "", t)
    t = code
    depth -= gsub(/\}/, "", t)
    if (depth < 0) depth = 99999
    if (depth == 0) { cur = ""; start = 0 }
  }
  END {
    if (bad) exit 1
    check_end()
    if (n > 0) print file >> ENVIRON["VM_TOUCHED"]
    print n + 0 >> ENVIRON["VM_COUNT"]
  }
'

# vendor/ and vendor/modules/ must be real directories inside the target, never symlinks leading out of it.
for p in vendor vendor/modules; do
  if [ -L "${target}/${p}" ]; then
    die "${target}/${p} is a symlink; refusing to write through it"
  fi
done
if [ -e "${target}/vendor/modules/VERSIONS" ]; then
  [ -f "${target}/vendor/modules/VERSIONS" ] && [ ! -L "${target}/vendor/modules/VERSIONS" ] ||
    die "vendor/modules/VERSIONS is not a regular file"
fi

# Everything is prepared under $work first: the vendored copies, the rewritten .tf files and VERSIONS.
# The target is only written after every module has gone through, so a failure up to that point changes nothing.
stage="${work}/stage"
mkdir -p "${stage}/tf" "${stage}/vendor"
for f in ${tf_files[@]+"${tf_files[@]}"}; do
  mkdir -p "${stage}/tf/$(dirname "$f")"
  cp "${target}/${f}" "${stage}/tf/${f}"
done
: >"${work}/touched"
if [ -f "${target}/vendor/modules/VERSIONS" ]; then
  cp "${target}/vendor/modules/VERSIONS" "${stage}/VERSIONS"
else
  : >"${stage}/VERSIONS"
fi

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
  mv "${work}/extract/modules/${name}" "${stage}/vendor/${name}"

  want="git::${url}//modules/${name}?ref=${tag}"
  prefix="git::${url}//modules/${name}?ref="
  rewritten=0
  rm -f "${work}/count"
  for f in ${tf_files[@]+"${tf_files[@]}"}; do
    dir="$(dirname "$f")"
    if [ "$dir" = "." ]; then
      rel="./vendor/modules/${name}"
    else
      ups="$(printf '%s\n' "$dir" | awk -F/ '{ s = ""; for (k = 1; k <= NF; k++) s = s "../"; print s }')"
      rel="${ups}vendor/modules/${name}"
    fi
    staged="${stage}/tf/${f}"

    # Exact string comparison of the quoted source value; nothing from the input is used as a regex.
    if [ -n "$url" ]; then
      awk -v want="$want" -v prefix="$prefix" -v repl="$rel" -v file="$f" -v report="${work}/report" \
        -v count="${work}/count" -v touched="${work}/touched" '
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
        END {
          if (n > 0) print file >> touched
          print n + 0 >> count
        }
      ' "$staged" >"${work}/out"
      mv "${work}/out" "$staged"
    fi

    if [ -n "$registry" ]; then
      VM_WANT="${registry}/${name}/aws" VM_VERSION="${tag##*-v}" VM_DIR="$dir" VM_FILE="$f" VM_REPL="$rel" \
        VM_RESOLVED="$resolved" VM_REPORT="${work}/report" VM_COUNT="${work}/count" VM_TOUCHED="${work}/touched" \
        awk "$registry_awk" "$staged" "$staged" >"${work}/out" || exit 1
      mv "${work}/out" "$staged"
    fi
  done
  if [ -f "${work}/count" ]; then
    rewritten="$(awk '{ s += $1 } END { print s + 0 }' "${work}/count")"
  fi

  # One line per module; a later run for the same module replaces its line.
  awk -v m="$name" '$1 != m' "${stage}/VERSIONS" >"${work}/versions"
  printf '%s %s %s\n' "$name" "$tag" "$commit" >>"${work}/versions"
  sort "${work}/versions" >"${stage}/VERSIONS"

  echo "vendored ${name} ${tag} (${commit}) into vendor/modules/${name}; rewrote ${rewritten} source line(s)"
  if [ "$rewritten" -eq 0 ]; then
    echo "warning: no source line pointed at module ${name} ${tag}" >&2
  fi
done

# Write to the target.
mkdir -p "${target}/vendor/modules"
vendor_dir="$(cd "${target}/vendor/modules" && pwd -P)"
[ "$vendor_dir" = "${target}/vendor/modules" ] || die "vendor/modules resolves outside the target: ${vendor_dir}"
for name in "${names[@]}"; do
  rm -rf "${vendor_dir:?}/${name:?}"
  mv "${stage}/vendor/${name}" "${vendor_dir}/${name}"
done
cat "${stage}/VERSIONS" >"${vendor_dir}/VERSIONS"
# Only files that had a rewrite are written back, so untouched files keep their bytes (for example a missing final newline).
while IFS= read -r f; do
  cat "${stage}/tf/${f}" >"${target}/${f}"
done < <(sort -u "${work}/touched")

if [ -s "${work}/report" ]; then
  echo "left unchanged (same module, different ref or version):" >&2
  sed 's/^/  /' "${work}/report" >&2
  exit 3
fi
