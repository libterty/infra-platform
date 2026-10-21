"""Pure functions of the traffic breaker. Standard library only; no AWS calls.

The breaker turns the listener or rule actions returned by Describe* into the actions
for Modify*: inside a weighted forward action the stable target group keeps (or gets) a
weight above zero and every other target group gets weight zero.
"""

import copy
import json

# The BREAKER_CONFIG schema this code understands. The module output lambda_config_json
# carries the same number; a mismatch means the image and the module version drifted (R12).
SUPPORTED_SCHEMA_VERSION = 1

TRIPPED_TAG_KEY = "traffic-breaker/tripped"

# ELBv2 treats a target group without Weight as weight 1.
_DEFAULT_WEIGHT = 1


class BreakerError(Exception):
    """Raised for configuration, event or listener states the breaker must not guess about."""


def parse_config(raw):
    """Parse the BREAKER_CONFIG JSON text into {alarm name: {listener_arn|rule_arn, stable_target_group_arn}}."""
    if not isinstance(raw, str):
        raise BreakerError("BREAKER_CONFIG is missing or not a string")
    try:
        doc = json.loads(raw)
    except ValueError as exc:
        raise BreakerError("BREAKER_CONFIG is not valid JSON: %s" % exc) from exc
    if not isinstance(doc, dict):
        raise BreakerError("BREAKER_CONFIG must be a JSON object")
    version = doc.get("schema_version")
    # bool is a subclass of int; reject it so that true does not pass as 1.
    if isinstance(version, bool) or version != SUPPORTED_SCHEMA_VERSION:
        raise BreakerError(
            "unsupported BREAKER_CONFIG schema_version %r; this image supports %d. "
            "Use an image tag that matches the module version." % (version, SUPPORTED_SCHEMA_VERSION)
        )
    alarms = doc.get("alarms")
    if not isinstance(alarms, dict):
        raise BreakerError("BREAKER_CONFIG.alarms must be an object")
    for name, entry in alarms.items():
        if not isinstance(entry, dict):
            raise BreakerError("BREAKER_CONFIG entry for %s must be an object" % name)
        if not entry.get("stable_target_group_arn"):
            raise BreakerError("BREAKER_CONFIG entry for %s has no stable_target_group_arn" % name)
        if bool(entry.get("listener_arn")) == bool(entry.get("rule_arn")):
            raise BreakerError("BREAKER_CONFIG entry for %s needs exactly one of listener_arn or rule_arn" % name)
    return alarms


def _weight(target_group):
    weight = target_group.get("Weight")
    return _DEFAULT_WEIGHT if weight is None else weight


def _forward_groups(action):
    """Return the target group entries of a forward action as a list."""
    forward_config = action.get("ForwardConfig")
    if forward_config and forward_config.get("TargetGroups"):
        return forward_config["TargetGroups"]
    if action.get("TargetGroupArn"):
        return [{"TargetGroupArn": action["TargetGroupArn"]}]
    return []


def _forward_actions(actions, stable_arn):
    """Return the forward actions, and fail unless every one of them contains the stable target group."""
    forwards = [a for a in actions if a.get("Type") == "forward"]
    if not forwards:
        raise BreakerError("no forward action found; refusing to modify")
    for action in forwards:
        if stable_arn not in [tg.get("TargetGroupArn") for tg in _forward_groups(action)]:
            raise BreakerError("stable target group %s is not in the forward action" % stable_arn)
    return forwards


def is_already_tripped(actions, stable_arn):
    """True when no forward action sends traffic to a target group other than the stable one."""
    for action in _forward_actions(actions, stable_arn):
        groups = _forward_groups(action)
        for tg in groups:
            if tg.get("TargetGroupArn") == stable_arn:
                if _weight(tg) <= 0 and len(groups) > 1:
                    return False
            elif _weight(tg) > 0:
                return False
    return True


def trip_actions(actions, stable_arn):
    """Return a new action list that routes only to the stable target group; the input is not modified.

    A forward with a single target group is returned unchanged. Everything else in the
    list (other actions, order, stickiness) is kept as Describe returned it, because
    Modify* replaces the whole action list.
    """
    _forward_actions(actions, stable_arn)
    result = copy.deepcopy(actions)
    for action in result:
        if action.get("Type") != "forward":
            continue
        groups = _forward_groups(action)
        if len(groups) <= 1 or not action.get("ForwardConfig"):
            continue
        for tg in action["ForwardConfig"]["TargetGroups"]:
            if tg.get("TargetGroupArn") == stable_arn:
                tg["Weight"] = _weight(tg) if _weight(tg) > 0 else 1
            else:
                tg["Weight"] = 0
    return result
