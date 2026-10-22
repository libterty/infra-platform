#!/usr/bin/env bash
# Static check of the install order (design C5): node pools -> NetworkPolicy setup -> controllers.
# terraform test cannot see depends_on, so this reads `terraform graph`. The graph is transitively reduced, so the check
# is reachability, not a direct edge: "A depends on B" means B is reachable from A.
# Needs `terraform init -backend=false` only; it never contacts AWS or a cluster.
# Usage: modules/eks-addons/tests/check-ordering.sh
set -euo pipefail

module_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v terraform >/dev/null || { echo "terraform not found" >&2; exit 1; }

data_dir="$(mktemp -d)"
trap 'rm -rf "$data_dir"; [ "${lock_existed:-1}" -eq 1 ] || rm -f "$module_dir/.terraform.lock.hcl"' EXIT
lock_existed=0
[ -f "$module_dir/.terraform.lock.hcl" ] && lock_existed=1
export TF_DATA_DIR="$data_dir"

terraform -chdir="$module_dir" init -backend=false -input=false >/dev/null
graph="$(terraform -chdir="$module_dir" graph)"

# Each line: <dependent> <dependency>. Both must be the same resource names as in main.tf.
expected="
system_network_policy auto_mode_nodes
load_balancer_controller system_network_policy
load_balancer_controller auto_mode_nodes
keda system_network_policy
keda auto_mode_nodes
keda load_balancer_controller
cloudwatch_observability system_network_policy
cloudwatch_observability auto_mode_nodes
cloudwatch_observability load_balancer_controller
crd_role_aggregation load_balancer_controller
"

# Prints "yes" when $2 is reachable from $1 following "dependent -> dependency" edges.
reachable() {
  printf '%s\n' "$graph" | awk -v from="helm_release.$1" -v to="helm_release.$2" '
    function clean(s) { gsub(/^[ \t]*"|"[ \t;]*$/, "", s); sub(/^\[root\] /, "", s); sub(/ \(expand\)$/, "", s); return s }
    / -> / {
      split($0, p, " -> ")
      a = clean(p[1]); b = clean(p[2])
      adj[a] = adj[a] " " b
    }
    END {
      n = 1; queue[1] = from; seen[from] = 1
      for (i = 1; i <= n; i++) {
        m = split(adj[queue[i]], next_nodes, " ")
        for (j = 1; j <= m; j++) {
          v = next_nodes[j]
          if (v == "" || (v in seen)) continue
          seen[v] = 1; queue[++n] = v
        }
      }
      print ((to in seen) ? "yes" : "no")
    }'
}

fail=0
while read -r dependent dependency; do
  [ -n "$dependent" ] || continue
  if [ "$(reachable "$dependent" "$dependency")" = "yes" ]; then
    echo "ok   helm_release.$dependent depends on helm_release.$dependency"
  else
    echo "FAIL helm_release.$dependent does not depend on helm_release.$dependency (add it to depends_on in main.tf)" >&2
    fail=1
  fi
done <<<"$expected"

# The check must be able to fail: a made-up edge in the wrong direction has to be reported as missing.
if [ "$(reachable auto_mode_nodes keda)" = "yes" ]; then
  echo "FAIL the graph says auto_mode_nodes depends on keda: the check or the graph is wrong" >&2
  fail=1
fi

exit "$fail"
