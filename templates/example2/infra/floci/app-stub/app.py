"""Stand-in for the api and worker images when example2 runs on Floci; the template ships no application code.

The api role (PORT is set) answers the ALB health check on /health. Every other path walks the dependencies the
stacks wire into the task, one hop at a time, and returns what each hop answered, so a single request shows the
request flow: the database through RDS Proxy, the two Redis groups, and the AgentCore Runtime. The worker role (no
PORT) reads one message from the stream Redis in a loop, which is what the real worker does with the api's stream.
"""

import json
import os
import socket
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Any, Callable

import boto3
import pg8000.native
import redis

STREAM_KEY = "floci:smoke"


def _secret_json(arn: str) -> dict[str, Any]:
    return json.loads(boto3.client("secretsmanager").get_secret_value(SecretId=arn)["SecretString"])


def _redis(prefix: str) -> redis.Redis:
    # The groups have transit encryption on, so <prefix>_TLS is "true" and the client speaks TLS, as the real api
    # does. The certificate is not verified: Floci's proxy presents one it made up.
    tls = os.environ.get(f"{prefix}_TLS", "false") == "true"
    return redis.Redis(
        host=os.environ[f"{prefix}_HOST"],
        port=int(os.environ[f"{prefix}_PORT"]),
        socket_timeout=5,
        ssl=tls,
        ssl_cert_reqs=None,
    )


def hop_database() -> dict[str, Any]:
    creds = _secret_json(os.environ["DB_SECRET_ARN"])
    conn = pg8000.native.Connection(
        user=creds["username"],
        password=creds["password"],
        host=os.environ["DB_HOST"],
        database=os.environ.get("DB_NAME", "postgres"),
        timeout=5,
    )
    try:
        version = conn.run("select version()")[0][0]
    finally:
        conn.close()
    return {"via": os.environ["DB_HOST"], "answer": version.split(" on ")[0]}


def hop_rate_limit_redis() -> dict[str, Any]:
    client = _redis("REDIS")
    count = client.incr("floci:requests")
    return {"via": f"{os.environ['REDIS_HOST']}:{os.environ['REDIS_PORT']}", "answer": f"request #{count}"}


def hop_stream_redis() -> dict[str, Any]:
    client = _redis("STREAM_REDIS")
    message_id = client.xadd(STREAM_KEY, {"from": "api", "at": str(time.time())}, maxlen=100)
    return {
        "via": f"{os.environ['STREAM_REDIS_HOST']}:{os.environ['STREAM_REDIS_PORT']}",
        "answer": f"XADD {message_id.decode()}",
    }


def hop_agent() -> dict[str, Any]:
    arn = json.loads(os.environ["AGENT_RUNTIME_ARNS"])
    runtime_arn = next(iter(arn.values())) if isinstance(arn, dict) else arn[0]
    reply = boto3.client("bedrock-agentcore").invoke_agent_runtime(
        agentRuntimeArn=runtime_arn, payload=json.dumps({"prompt": "ping"}).encode()
    )
    body = reply["response"].read().decode()
    return {"via": runtime_arn, "answer": body[:200]}


HOPS: list[tuple[str, Callable[[], dict[str, Any]]]] = [
    ("database (RDS Proxy -> Aurora)", hop_database),
    ("rate-limit Redis", hop_rate_limit_redis),
    ("stream Redis", hop_stream_redis),
    ("AgentCore Runtime", hop_agent),
]


def trace(path: str) -> dict[str, Any]:
    hops = []
    for name, hop in HOPS:
        started = time.monotonic()
        try:
            result = {"ok": True, **hop()}
        except Exception as exc:  # noqa: BLE001 - the trace reports every hop, including the failing ones
            result = {"ok": False, "error": f"{type(exc).__name__}: {exc}"[:300]}
        result["ms"] = round((time.monotonic() - started) * 1000)
        hops.append({"hop": name, **result})
    return {"service": "api", "task": socket.gethostname(), "path": path, "hops": hops}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802 - http.server naming
        if self.path == "/health":
            self._send(200, {"status": "ok"})
            return
        self._send(200, trace(self.path))

    def _send(self, status: int, body: dict[str, Any]) -> None:
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def run_worker() -> None:
    client = _redis("STREAM_REDIS")
    last = "$"
    while True:
        try:
            for _, messages in client.xread({STREAM_KEY: last}, block=10000, count=10) or []:
                for message_id, fields in messages:
                    last = message_id
                    print(f"worker consumed {message_id.decode()} {fields}", flush=True)
        except redis.RedisError as exc:
            print(f"worker waiting for stream Redis: {exc}", flush=True)
            time.sleep(5)


if __name__ == "__main__":
    if os.environ.get("PORT"):
        HTTPServer(("0.0.0.0", int(os.environ["PORT"])), Handler).serve_forever()
    else:
        run_worker()
