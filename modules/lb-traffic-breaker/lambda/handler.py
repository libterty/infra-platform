"""Lambda entry point: CloudWatch alarm in ALARM state -> shift the listener or rule to the stable target group.

boto3 is imported only when no client is injected, so the unit tests need no AWS SDK.
"""

import logging
import os

import breaker

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _parse_event(event):
    """Return (alarm name, state) from the CloudWatch alarm event (alarmData.alarmName, alarmData.state.value)."""
    if not isinstance(event, dict):
        raise breaker.BreakerError("event is not an object")
    alarm_data = event.get("alarmData")
    if not isinstance(alarm_data, dict):
        raise breaker.BreakerError("event has no alarmData")
    name = alarm_data.get("alarmName")
    state = (alarm_data.get("state") or {}).get("value")
    if not name or not state:
        raise breaker.BreakerError("event has no alarmData.alarmName or alarmData.state.value")
    return name, state


def _describe_actions(client, target):
    if target.get("rule_arn"):
        rules = client.describe_rules(RuleArns=[target["rule_arn"]]).get("Rules", [])
        if not rules:
            raise breaker.BreakerError("rule %s not found" % target["rule_arn"])
        return rules[0]["Actions"]
    listeners = client.describe_listeners(ListenerArns=[target["listener_arn"]]).get("Listeners", [])
    if not listeners:
        raise breaker.BreakerError("listener %s not found" % target["listener_arn"])
    return listeners[0]["DefaultActions"]


def _modify(client, target, actions):
    if target.get("rule_arn"):
        client.modify_rule(RuleArn=target["rule_arn"], Actions=actions)
    else:
        client.modify_listener(ListenerArn=target["listener_arn"], DefaultActions=actions)


def handle_event(event, config, client):
    """Process one alarm event with an elbv2 client; returns a small status dict."""
    name, state = _parse_event(event)
    if state != "ALARM":
        logger.info("ignoring alarm %s in state %s", name, state)
        return {"status": "ignored", "alarm": name, "state": state}
    target = config.get(name)
    if target is None:
        raise breaker.BreakerError("alarm %s is not in BREAKER_CONFIG" % name)
    resource_arn = target.get("rule_arn") or target["listener_arn"]
    stable_arn = target["stable_target_group_arn"]

    actions = _describe_actions(client, target)
    if breaker.is_already_tripped(actions, stable_arn):
        logger.info("%s is already routed to the stable target group; nothing to do (alarm %s)", resource_arn, name)
        return {"status": "already_tripped", "alarm": name, "resource": resource_arn}

    _modify(client, target, breaker.trip_actions(actions, stable_arn))
    # Tag after Modify: a failed Modify must not leave a tripped marker behind.
    client.add_tags(ResourceArns=[resource_arn], Tags=[{"Key": breaker.TRIPPED_TAG_KEY, "Value": name}])
    logger.info("tripped %s to stable target group %s (alarm %s)", resource_arn, stable_arn, name)
    return {"status": "tripped", "alarm": name, "resource": resource_arn}


def lambda_handler(event, context, environ=None, client=None):
    """AWS entry point. environ and client are injectable for tests."""
    environ = os.environ if environ is None else environ
    try:
        config = breaker.parse_config(environ.get("BREAKER_CONFIG"))
        if client is None:
            import boto3  # provided by the Lambda runtime

            client = boto3.client("elbv2")
        return handle_event(event, config, client)
    except Exception:
        # Re-raise so Lambda records the failure and retries the asynchronous invocation.
        logger.exception("traffic breaker failed for event %s", event)
        raise
