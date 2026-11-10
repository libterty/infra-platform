"""Print the api stub's trace response (stdin) as one line per hop.

Exit 0 when every hop answered or failed only in a way listed in KNOWN_GAPS, 1 when a hop failed otherwise, 2 when
the body is not a trace.
"""

import json
import sys

# Hops that cannot pass on Floci 2.4.0, keyed by hop name prefix, with the error prefix that marks the known gap.
# The groups have transit encryption and no AUTH token, which AWS serves over TLS without a password; Floci's cache
# proxy accepts the TLS connection but still asks for AUTH. Reaching that prompt proves the endpoint, port and TLS
# wiring; anything else (refused, timeout, plain-text close) is a real failure.
KNOWN_GAPS = {
    "rate-limit Redis": "AuthenticationError",
    "stream Redis": "AuthenticationError",
}


def main() -> int:
    try:
        trace = json.load(sys.stdin)
        hops = trace["hops"]
    except (ValueError, KeyError, TypeError):
        return 2
    print(f"    ALB → ECS service {trace['service']}（task {trace['task']}），path {trace['path']}")
    failed = 0
    for hop in hops:
        detail = hop.get("answer") or hop.get("error") or ""
        if hop["ok"]:
            mark = "OK"
        elif detail.startswith(KNOWN_GAPS.get(hop["hop"], "\0")):
            mark = "KN"
            detail += "（Floci 已知限制：TLS 已連上 cache proxy，但 Floci 要求 AUTH，AWS 不會）"
        else:
            mark = "NG"
            failed += 1
        print(f"    {mark}  api → {hop['hop']:<32} {hop['ms']:>5} ms  {hop.get('via', '')}")
        print(f"          {detail}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
