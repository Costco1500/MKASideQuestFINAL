import copy
import unittest
from unittest.mock import Mock
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

if __name__ == "__main__": unittest.main()
