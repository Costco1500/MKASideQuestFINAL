import copy
import io
import json
import unittest
from unittest.mock import Mock, patch
from planner import generate, demo_plans, validate_request, validate_plans

def context():
    window = {"start": "2026-10-01T18:00:00Z", "end": "2026-10-01T21:00:00Z"}
    return {"participants": [{"id": "alex", "ageRange": "18–20", "maxBudget": 15,
            "approximateArea": "Midtown", "availability": [window]}],
            "selectedMessages": [{"sender": "Alex", "text": "Quiet, please"}],
            "candidateTimeWindows": [window], "timeZone": "UTC"}

class PlannerTests(unittest.TestCase):
    def test_valid_response_needs_one_call(self):
        request = context()
        call = Mock(return_value={"plans": demo_plans(request)})
        result = generate(request, call)
        self.assertEqual(result["source"], "ai")
        self.assertEqual(call.call_count, 1)

    def test_invalid_output_retries_at_most_once_then_demo(self):
        call = Mock(return_value={"plans": []})
        result = generate(context(), call)
        self.assertEqual(call.call_count, 2)
        self.assertEqual(result["source"], "demo")
        self.assertEqual(len(result["plans"]), 3)

    def test_network_unavailable_falls_back_without_retry(self):
        call = Mock(side_effect=OSError("offline"))
        self.assertEqual(generate(context(), call)["source"], "demo")
        self.assertEqual(call.call_count, 1)

    def test_hard_constraints_are_validated(self):
        for field, value in [("estimatedCostPerPerson", 16), ("minimumAge", 21),
                             ("start", "2026-10-01T17:00:00Z"), ("area", "Another city")]:
            plans = demo_plans(context()); plans[0][field] = value
            self.assertFalse(validate_plans(plans, context()), field)

    def test_unknown_fields_and_excess_context_are_rejected(self):
        request = context(); request["calendarTitles"] = ["private"]
        with self.assertRaises(ValueError): validate_request(request)
        request = context(); request["selectedMessages"] *= 51
        with self.assertRaises(ValueError): validate_request(request)

    def test_unavailable_or_overnight_candidates_rejected(self):
        request = context(); request["candidateTimeWindows"][0] = {"start": "2026-10-01T23:00:00Z", "end": "2026-10-02T02:00:00Z"}
        with self.assertRaises(ValueError): validate_request(request)

    def test_demo_zero_budget_and_no_window(self):
        request = context(); request["participants"][0]["maxBudget"] = 0
        self.assertTrue(all(p["estimatedCostPerPerson"] == 0 for p in demo_plans(request)))
        request["candidateTimeWindows"] = []
        with self.assertRaises(ValueError): generate(request)

    def test_malformed_profiles_messages_and_windows_are_rejected(self):
        changes = [
            lambda r: r.update(participants=[]),
            lambda r: r["participants"].append(copy.deepcopy(r["participants"][0])),
            lambda r: r["participants"][0].update(extra="private"),
            lambda r: r["participants"][0].update(id=""),
            lambda r: r["participants"][0].update(maxBudget=-1),
            lambda r: r["participants"][0].update(ageRange="unknown"),
            lambda r: r["participants"][0].update(availability=[]),
            lambda r: r["participants"][0]["availability"][0].update(end="2026-10-01T18:00:00Z"),
            lambda r: r["selectedMessages"][0].update(text=""),
            lambda r: r.update(timeZone="Not/AZone"),
            lambda r: r.update(candidateTimeWindows=[{"start": "2026-10-01T10:00:00Z", "end": "2026-10-01T12:00:00Z"}]),
        ]
        for mutate in changes:
            request = copy.deepcopy(context()); mutate(request)
            with self.subTest(request=request), self.assertRaises(ValueError): validate_request(request)

    def test_invalid_model_fields_and_repair_response(self):
        for field, value in [("title", ""), ("estimatedCostPerPerson", float("nan")), ("groupFitScore", 101),
                             ("minimumAge", -1), ("secondStop", 1), ("concerns", "wrong type"), ("whyItWorks", {})]:
            plans = demo_plans(context()); plans[0][field] = value
            self.assertFalse(validate_plans(plans, context()), field)
        plans = demo_plans(context()); plans[0]["id"] = plans[1]["id"]
        self.assertFalse(validate_plans(plans, context()))
        repair = Mock(side_effect=[ValueError("invalid JSON"), {"plans": demo_plans(context())}])
        self.assertEqual(generate(context(), repair)["source"], "ai")
        self.assertEqual(repair.call_count, 2)

    def test_openai_wire_format_is_single_structured_request(self):
        response = {"choices": [{"message": {"content": json.dumps({"plans": demo_plans(context())})}}]}
        with patch.dict("os.environ", {"OPENAI_API_KEY": "test-only-placeholder"}), patch("planner.urllib.request.urlopen", return_value=io.BytesIO(json.dumps(response).encode())) as send:
            self.assertEqual(generate(context())["source"], "ai")
            self.assertEqual(send.call_count, 1)
            payload = json.loads(send.call_args.args[0].data)
            self.assertTrue(payload["response_format"]["json_schema"]["strict"])
            self.assertEqual(len(payload["messages"]), 2)
            self.assertEqual(json.loads(payload["messages"][1]["content"]), context())

    def test_llm_supplies_search_terms_and_never_authoritative_coordinates(self):
        from planner import schema
        properties = schema(context())["properties"]["plans"]["items"]["properties"]
        self.assertIn("venueSearchQuery", properties)
        self.assertNotIn("venue", properties)
        invented = demo_plans(context())
        invented[0]["venue"] = {"name": "Invented", "latitude": 1, "longitude": 2}
        result = generate(context(), Mock(return_value={"plans": invented}))
        self.assertEqual(result["source"], "demo")
        self.assertTrue(all("venue" not in plan for plan in result["plans"]))

    def test_response_schema_constrains_lowest_budget_age_and_supplied_areas(self):
        from planner import schema
        request = context()
        request["participants"].append(dict(request["participants"][0], id="maya", maxBudget=5, ageRange="under18", approximateArea="Campus"))
        fields = schema(request)["properties"]["plans"]["items"]["properties"]
        self.assertEqual(fields["estimatedCostPerPerson"]["maximum"], 5)
        self.assertEqual(fields["estimatedCostPerPerson"]["minimum"], 0)
        self.assertEqual(fields["minimumAge"]["maximum"], 0)
        self.assertCountEqual(fields["area"]["enum"], ["Midtown", "Campus"])

    def test_map_queries_are_short_single_search_inputs(self):
        from planner import schema
        field = schema(context())["properties"]["plans"]["items"]["properties"]["venueSearchQuery"]
        self.assertEqual(field["maxLength"], 80)
        plans = demo_plans(context()); plans[0]["venueSearchQuery"] = "a" * 81
        self.assertFalse(validate_plans(plans, context()))

if __name__ == "__main__": unittest.main()
