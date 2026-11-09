"""Stand-in for the API image when example6 runs on Floci; the template ships no application code.

It follows the API's contract (design K17): a request without the origin verify header gets 403. Past that check it
proves the wiring the stacks create: the function's environment names a secret it can read and a table it can write
to and read back.
"""

import hmac
import json
import os
import time
from typing import Any

import boto3


def _response(status: int, body: dict[str, Any]) -> dict[str, Any]:
    return {"statusCode": status, "headers": {"content-type": "application/json"}, "body": json.dumps(body)}


def handler(event: dict[str, Any], _context: Any) -> dict[str, Any]:
    expected = boto3.client("secretsmanager").get_secret_value(SecretId=os.environ["ORIGIN_VERIFY_SECRET_ARN"])[
        "SecretString"
    ]
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    sent = headers.get(os.environ["ORIGIN_VERIFY_HEADER_NAME"].lower(), "")
    if not hmac.compare_digest(sent, expected):
        return _response(403, {"message": "forbidden"})

    table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
    key = {"PK": "floci#smoke", "SK": str(time.time_ns())}
    table.put_item(Item=key)
    found = table.get_item(Key=key).get("Item") is not None
    return _response(200, {"route": event.get("routeKey", ""), "table": table.name, "write_read_ok": found})
