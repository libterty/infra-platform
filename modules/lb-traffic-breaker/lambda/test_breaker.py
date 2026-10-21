"""Unit tests for breaker.py and handler.py. Standard library only: boto3 is never imported."""

import copy
import json
import logging
import unittest

import breaker
import handler

def setUpModule():
    # The handler logs failures with a traceback; keep the test output readable.
    logging.disable(logging.CRITICAL)


def tearDownModule():
    logging.disable(logging.NOTSET)


REGION_ACCOUNT = "ap-northeast-1:111111111111"
STABLE = f"arn:aws:elasticloadbalancing:{REGION_ACCOUNT}:targetgroup/dev-old/1111111111111111"
CANARY = f"arn:aws:elasticloadbalancing:{REGION_ACCOUNT}:targetgroup/dev-new/2222222222222222"
LISTENER = f"arn:aws:elasticloadbalancing:{REGION_ACCOUNT}:listener/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa"
RULE = f"arn:aws:elasticloadbalancing:{REGION_ACCOUNT}:listener-rule/app/dev-web/0123456789abcdef/aaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbb"
ALARM = "dev-web-api-error-rate"


def weighted_forward(stable_weight=50, canary_weight=50, stickiness=None, order=1):
    config = {
        "TargetGroups": [
            {"TargetGroupArn": STABLE, "Weight": stable_weight},
            {"TargetGroupArn": CANARY, "Weight": canary_weight},
        ]
    }
    if stickiness is not None:
        config["TargetGroupStickinessConfig"] = stickiness
    return {"Type": "forward", "Order": order, "ForwardConfig": config}


def weights(actions):
    return {tg["TargetGroupArn"]: tg["Weight"] for tg in actions[0]["ForwardConfig"]["TargetGroups"]}


class TripActionsTest(unittest.TestCase):
    def test_two_target_groups_become_stable_only(self):
        result = breaker.trip_actions([weighted_forward(50, 50)], STABLE)
        self.assertEqual(weights(result), {STABLE: 50, CANARY: 0})

    def test_stable_with_zero_weight_gets_weight_one(self):
        result = breaker.trip_actions([weighted_forward(0, 100)], STABLE)
        self.assertEqual(weights(result), {STABLE: 1, CANARY: 0})

    def test_stable_without_weight_field_gets_weight_one(self):
        action = weighted_forward()
        del action["ForwardConfig"]["TargetGroups"][0]["Weight"]
        result = breaker.trip_actions([action], STABLE)
        self.assertEqual(weights(result), {STABLE: 1, CANARY: 0})

    def test_three_target_groups_only_stable_keeps_weight(self):
        other = f"arn:aws:elasticloadbalancing:{REGION_ACCOUNT}:targetgroup/dev-other/3333333333333333"
        action = weighted_forward(10, 20)
        action["ForwardConfig"]["TargetGroups"].append({"TargetGroupArn": other, "Weight": 30})
        result = breaker.trip_actions([action], STABLE)
        self.assertEqual(weights(result), {STABLE: 10, CANARY: 0, other: 0})

    def test_input_is_not_mutated(self):
        actions = [weighted_forward(50, 50)]
        snapshot = copy.deepcopy(actions)
        breaker.trip_actions(actions, STABLE)
        self.assertEqual(actions, snapshot)

    def test_stickiness_is_preserved(self):
        stickiness = {"Enabled": True, "DurationSeconds": 600}
        result = breaker.trip_actions([weighted_forward(stickiness=stickiness)], STABLE)
        self.assertEqual(result[0]["ForwardConfig"]["TargetGroupStickinessConfig"], stickiness)

    def test_order_and_type_are_preserved(self):
        result = breaker.trip_actions([weighted_forward(order=3)], STABLE)
        self.assertEqual(result[0]["Order"], 3)
        self.assertEqual(result[0]["Type"], "forward")

    def test_non_forward_actions_are_kept_in_place(self):
        auth = {"Type": "authenticate-cognito", "Order": 1, "AuthenticateCognitoConfig": {"UserPoolArn": "x"}}
        forward = weighted_forward(order=2)
        result = breaker.trip_actions([auth, forward], STABLE)
        self.assertEqual(result[0], auth)
        self.assertEqual(result[1]["ForwardConfig"]["TargetGroups"][1]["Weight"], 0)

    def test_single_target_group_forward_is_left_alone(self):
        action = {"Type": "forward", "Order": 1, "TargetGroupArn": STABLE}
        result = breaker.trip_actions([action], STABLE)
        self.assertEqual(result, [action])

    def test_single_entry_forward_config_is_left_alone(self):
        action = {
            "Type": "forward",
            "TargetGroupArn": STABLE,
            "ForwardConfig": {"TargetGroups": [{"TargetGroupArn": STABLE, "Weight": 1}]},
        }
        self.assertEqual(breaker.trip_actions([action], STABLE), [action])

    def test_stable_missing_from_forward_raises(self):
        other = f"arn:aws:elasticloadbalancing:{REGION_ACCOUNT}:targetgroup/dev-x/4444444444444444"
        with self.assertRaises(breaker.BreakerError):
            breaker.trip_actions([weighted_forward()], other)

    def test_single_target_group_that_is_not_stable_raises(self):
        action = {"Type": "forward", "TargetGroupArn": CANARY}
        with self.assertRaises(breaker.BreakerError):
            breaker.trip_actions([action], STABLE)

    def test_no_forward_action_raises(self):
        with self.assertRaises(breaker.BreakerError):
            breaker.trip_actions([{"Type": "fixed-response", "FixedResponseConfig": {"StatusCode": "503"}}], STABLE)

    def test_empty_actions_raise(self):
        with self.assertRaises(breaker.BreakerError):
            breaker.trip_actions([], STABLE)


class IsAlreadyTrippedTest(unittest.TestCase):
    def test_weighted_canary_is_not_tripped(self):
        self.assertFalse(breaker.is_already_tripped([weighted_forward(50, 50)], STABLE))

    def test_stable_only_is_tripped(self):
        self.assertTrue(breaker.is_already_tripped([weighted_forward(1, 0)], STABLE))

    def test_canary_only_is_not_tripped(self):
        self.assertFalse(breaker.is_already_tripped([weighted_forward(0, 100)], STABLE))

    def test_missing_weight_counts_as_one(self):
        action = weighted_forward(0, 0)
        del action["ForwardConfig"]["TargetGroups"][1]["Weight"]
        self.assertFalse(breaker.is_already_tripped([action], STABLE))

    def test_result_of_trip_actions_is_tripped(self):
        tripped = breaker.trip_actions([weighted_forward(50, 50)], STABLE)
        self.assertTrue(breaker.is_already_tripped(tripped, STABLE))
        self.assertEqual(breaker.trip_actions(tripped, STABLE), tripped)

    def test_single_target_group_stable_is_tripped(self):
        self.assertTrue(breaker.is_already_tripped([{"Type": "forward", "TargetGroupArn": STABLE}], STABLE))

    def test_stable_missing_raises(self):
        with self.assertRaises(breaker.BreakerError):
            breaker.is_already_tripped([{"Type": "forward", "TargetGroupArn": CANARY}], STABLE)


class ParseConfigTest(unittest.TestCase):
    def config(self, **override):
        doc = {
            "schema_version": 1,
            "alarms": {
                ALARM: {"listener_arn": LISTENER, "stable_target_group_arn": STABLE},
                "dev-web-api-healthy-hosts": {"rule_arn": RULE, "stable_target_group_arn": STABLE},
            },
        }
        doc.update(override)
        return json.dumps(doc)

    def test_known_schema_version_is_parsed(self):
        parsed = breaker.parse_config(self.config())
        self.assertEqual(parsed[ALARM], {"listener_arn": LISTENER, "stable_target_group_arn": STABLE})
        self.assertEqual(parsed["dev-web-api-healthy-hosts"]["rule_arn"], RULE)

    def test_unknown_schema_version_raises(self):
        with self.assertRaises(breaker.BreakerError):
            breaker.parse_config(self.config(schema_version=2))

    def test_missing_schema_version_raises(self):
        doc = json.loads(self.config())
        del doc["schema_version"]
        with self.assertRaises(breaker.BreakerError):
            breaker.parse_config(json.dumps(doc))

    def test_string_schema_version_raises(self):
        with self.assertRaises(breaker.BreakerError):
            breaker.parse_config(self.config(schema_version="1"))

    def test_invalid_json_raises(self):
        with self.assertRaises(breaker.BreakerError):
            breaker.parse_config("{not json")

    def test_none_raises(self):
        with self.assertRaises(breaker.BreakerError):
            breaker.parse_config(None)

    def test_entry_with_both_listener_and_rule_raises(self):
        alarms = {ALARM: {"listener_arn": LISTENER, "rule_arn": RULE, "stable_target_group_arn": STABLE}}
        with self.assertRaises(breaker.BreakerError):
            breaker.parse_config(self.config(alarms=alarms))

    def test_entry_with_neither_listener_nor_rule_raises(self):
        alarms = {ALARM: {"stable_target_group_arn": STABLE}}
        with self.assertRaises(breaker.BreakerError):
            breaker.parse_config(self.config(alarms=alarms))

    def test_entry_without_stable_raises(self):
        alarms = {ALARM: {"listener_arn": LISTENER}}
        with self.assertRaises(breaker.BreakerError):
            breaker.parse_config(self.config(alarms=alarms))


class FakeElbv2:
    """Records calls like the boto3 elbv2 client, with the subset of the API the handler uses."""

    def __init__(self, actions):
        self.actions = actions
        self.calls = []

    def describe_listeners(self, **kwargs):
        self.calls.append(("describe_listeners", kwargs))
        return {"Listeners": [{"ListenerArn": kwargs["ListenerArns"][0], "DefaultActions": self.actions}]}

    def describe_rules(self, **kwargs):
        self.calls.append(("describe_rules", kwargs))
        return {"Rules": [{"RuleArn": kwargs["RuleArns"][0], "Actions": self.actions}]}

    def modify_listener(self, **kwargs):
        self.calls.append(("modify_listener", kwargs))
        return {}

    def modify_rule(self, **kwargs):
        self.calls.append(("modify_rule", kwargs))
        return {}

    def add_tags(self, **kwargs):
        self.calls.append(("add_tags", kwargs))
        return {}

    def names(self):
        return [name for name, _ in self.calls]


def alarm_event(name=ALARM, state="ALARM"):
    return {
        "source": "aws.cloudwatch",
        "alarmArn": f"arn:aws:cloudwatch:{REGION_ACCOUNT}:alarm:{name}",
        "accountId": "111111111111",
        "time": "2026-10-21T12:36:15.490+0000",
        "region": "ap-northeast-1",
        "alarmData": {
            "alarmName": name,
            "state": {"value": state, "reason": "threshold crossed", "timestamp": "2026-10-21T12:36:15.490+0000"},
            "previousState": {"value": "OK"},
        },
    }


CONFIG = {
    ALARM: {"listener_arn": LISTENER, "stable_target_group_arn": STABLE},
    "dev-web-api-healthy-hosts": {"rule_arn": RULE, "stable_target_group_arn": STABLE},
}


class HandleEventTest(unittest.TestCase):
    def test_alarm_on_listener_describes_modifies_and_tags(self):
        client = FakeElbv2([weighted_forward(50, 50, stickiness={"Enabled": False})])
        result = handler.handle_event(alarm_event(), CONFIG, client)
        self.assertEqual(result["status"], "tripped")
        self.assertEqual(client.names(), ["describe_listeners", "modify_listener", "add_tags"])
        modify = client.calls[1][1]
        self.assertEqual(modify["ListenerArn"], LISTENER)
        self.assertEqual(weights(modify["DefaultActions"]), {STABLE: 50, CANARY: 0})
        self.assertEqual(
            modify["DefaultActions"][0]["ForwardConfig"]["TargetGroupStickinessConfig"], {"Enabled": False}
        )
        tags = client.calls[2][1]
        self.assertEqual(tags["ResourceArns"], [LISTENER])
        self.assertEqual(tags["Tags"], [{"Key": "traffic-breaker/tripped", "Value": ALARM}])

    def test_alarm_on_rule_uses_rule_api(self):
        client = FakeElbv2([weighted_forward(50, 50)])
        result = handler.handle_event(alarm_event("dev-web-api-healthy-hosts"), CONFIG, client)
        self.assertEqual(result["status"], "tripped")
        self.assertEqual(client.names(), ["describe_rules", "modify_rule", "add_tags"])
        modify = client.calls[1][1]
        self.assertEqual(modify["RuleArn"], RULE)
        self.assertEqual(weights(modify["Actions"]), {STABLE: 50, CANARY: 0})
        self.assertEqual(client.calls[2][1]["ResourceArns"], [RULE])

    def test_already_tripped_does_not_modify(self):
        client = FakeElbv2([weighted_forward(1, 0)])
        result = handler.handle_event(alarm_event(), CONFIG, client)
        self.assertEqual(result["status"], "already_tripped")
        self.assertEqual(client.names(), ["describe_listeners"])

    def test_ok_state_is_ignored_without_any_call(self):
        client = FakeElbv2([weighted_forward()])
        result = handler.handle_event(alarm_event(state="OK"), CONFIG, client)
        self.assertEqual(result["status"], "ignored")
        self.assertEqual(client.calls, [])

    def test_insufficient_data_is_ignored(self):
        client = FakeElbv2([weighted_forward()])
        self.assertEqual(handler.handle_event(alarm_event(state="INSUFFICIENT_DATA"), CONFIG, client)["status"], "ignored")
        self.assertEqual(client.calls, [])

    def test_unknown_alarm_raises_without_any_call(self):
        client = FakeElbv2([weighted_forward()])
        with self.assertRaises(breaker.BreakerError):
            handler.handle_event(alarm_event("someone-elses-alarm"), CONFIG, client)
        self.assertEqual(client.calls, [])

    def test_event_without_alarm_data_raises(self):
        with self.assertRaises(breaker.BreakerError):
            handler.handle_event({"source": "aws.cloudwatch"}, CONFIG, FakeElbv2([]))

    def test_event_without_state_raises(self):
        event = alarm_event()
        del event["alarmData"]["state"]
        with self.assertRaises(breaker.BreakerError):
            handler.handle_event(event, CONFIG, FakeElbv2([]))

    def test_non_dict_event_raises(self):
        for bad in (None, "x", [], 1):
            with self.assertRaises(breaker.BreakerError):
                handler.handle_event(bad, CONFIG, FakeElbv2([]))

    def test_listener_not_found_raises(self):
        class Empty(FakeElbv2):
            def describe_listeners(self, **kwargs):
                return {"Listeners": []}

        with self.assertRaises(breaker.BreakerError):
            handler.handle_event(alarm_event(), CONFIG, Empty([]))

    def test_modify_failure_propagates_and_skips_tag(self):
        class Failing(FakeElbv2):
            def modify_listener(self, **kwargs):
                raise RuntimeError("AccessDenied")

        client = Failing([weighted_forward()])
        with self.assertRaises(RuntimeError):
            handler.handle_event(alarm_event(), CONFIG, client)
        self.assertNotIn("add_tags", client.names())

    def test_stable_missing_in_forward_raises_and_does_not_modify(self):
        client = FakeElbv2([{"Type": "forward", "TargetGroupArn": CANARY}])
        with self.assertRaises(breaker.BreakerError):
            handler.handle_event(alarm_event(), CONFIG, client)
        self.assertEqual(client.names(), ["describe_listeners"])


class LambdaHandlerTest(unittest.TestCase):
    def test_unknown_schema_version_in_environment_raises(self):
        env = {"BREAKER_CONFIG": json.dumps({"schema_version": 99, "alarms": {}})}
        with self.assertRaises(breaker.BreakerError):
            handler.lambda_handler(alarm_event(), None, environ=env, client=FakeElbv2([]))

    def test_missing_environment_variable_raises(self):
        with self.assertRaises(breaker.BreakerError):
            handler.lambda_handler(alarm_event(), None, environ={}, client=FakeElbv2([]))

    def test_end_to_end_with_injected_client(self):
        env = {"BREAKER_CONFIG": json.dumps({"schema_version": 1, "alarms": CONFIG})}
        client = FakeElbv2([weighted_forward(50, 50)])
        result = handler.lambda_handler(alarm_event(), None, environ=env, client=client)
        self.assertEqual(result["status"], "tripped")


if __name__ == "__main__":
    unittest.main()
